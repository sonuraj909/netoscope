import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Consume the request like a real transport, driving upload progress.
    await requestStream?.drain<void>();
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Netoscope netoscope;
  late Dio dio;

  void setUpDio(ResponseBody Function(RequestOptions) respond) {
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    dio = Dio(BaseOptions(baseUrl: 'https://api.dev'))
      ..httpClientAdapter = _Adapter(respond)
      ..interceptors.add(netoscope.dioInterceptor);
  }

  tearDown(() => netoscope.dispose());

  test('recognizes GraphQL sent as a map', () async {
    setUpDio(
      (_) => ResponseBody.fromString(
        '{"data":{"login":null},"errors":[{"message":"bad password"}]}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );

    await dio.post<void>(
      '/graphql',
      data: {
        'query': r'mutation Login($password: String!) '
            r'{ login(password: $password) { token } }',
        'variables': {'password': 'hunter2'},
      },
    );

    final graphQL = netoscope.logs.single.graphQL!;
    expect(graphQL.operations.single.type, GraphQLOperationType.mutation);
    // Variables are redacted by key name, like every other structure.
    expect(graphQL.operations.single.variables, '{"password":"***"}');
    expect(graphQL.errors.single.message, 'bad password');
  });

  test('describes webhook attempts passed in extra', () async {
    setUpDio((_) => ResponseBody.fromString('', 202));

    await dio.post<void>(
      '/hooks',
      data: {'id': 1},
      options: Options(
        extra: {
          Netoscope.webhookKey: const WebhookAttempt(
            eventType: 'invoice.paid',
            deliveryId: 'd-1',
            attempt: 2,
            maxAttempts: 5,
          ),
        },
      ),
    );

    final webhook = netoscope.logs.single.webhook!;
    expect(webhook.outcome, WebhookOutcome.delivered);
    expect(webhook.attempt, 2);
    expect(webhook.eventType, 'invoice.paid');
  });

  test('records progress without changing what the app receives', () async {
    final payload = 'x' * 4096;
    setUpDio((_) => ResponseBody.fromString(payload, 200));
    final sent = <int>[];
    final received = <int>[];

    final response = await dio.post<String>(
      '/upload',
      data: 'y' * 2048,
      options: Options(
        headers: {Headers.contentLengthHeader: 2048},
        responseType: ResponseType.plain,
      ),
      onSendProgress: (count, total) => sent.add(count),
      onReceiveProgress: (count, total) => received.add(count),
    );

    expect(response.data, payload);
    expect(sent, isNotEmpty);
    expect(received, isNotEmpty);
    final transfers =
        netoscope.logs.single.details.whereType<TransferDetails>();
    final upload =
        transfers.firstWhere((t) => t.direction == TransferDirection.upload);
    final download =
        transfers.firstWhere((t) => t.direction == TransferDirection.download);
    expect(upload.bytesTransferred, sent.last);
    expect(download.bytesTransferred, received.last);
  });

  test('requests without progress callbacks get none added', () async {
    setUpDio((_) => ResponseBody.fromString('ok', 200));
    late RequestOptions seen;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          seen = options;
          handler.next(options);
        },
      ),
    );

    await dio.get<void>('/plain');

    expect(seen.onSendProgress, isNull);
    expect(seen.onReceiveProgress, isNull);
    expect(netoscope.logs.single.details, isEmpty);
  });

  test('payload decoders receive the request URL and direction', () async {
    final contexts = <PayloadContext>[];
    netoscope = Netoscope(
      config: NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        payloadDecoders: [
          ProtobufPayloadDecoder(
            decode: (bytes, context) {
              contexts.add(context);
              return {'size': bytes.length};
            },
          ),
        ],
      ),
    );
    dio = Dio(BaseOptions(baseUrl: 'https://api.dev'))
      ..httpClientAdapter = _Adapter(
        (_) => ResponseBody.fromBytes(
          [1, 2, 3],
          200,
          headers: {
            Headers.contentTypeHeader: ['application/x-protobuf'],
          },
        ),
      )
      ..interceptors.add(netoscope.dioInterceptor);

    await dio.get<List<int>>(
      '/item',
      options: Options(responseType: ResponseType.bytes),
    );

    expect(contexts.single.url!.path, '/item');
    expect(contexts.single.direction, MessageDirection.incoming);
    final body = netoscope.logs.single.responseBody!;
    expect(body.format, PayloadFormat.protobuf);
    expect(jsonDecode(body.content), {'size': 3});
  });
}
