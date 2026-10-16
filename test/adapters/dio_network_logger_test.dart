import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

typedef _Handler = Future<ResponseBody> Function(
  RequestOptions options,
  Future<void>? cancelFuture,
);

/// A deterministic transport so tests never touch the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  _Handler handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options, cancelFuture);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  late Netoscope netoscope;
  late _FakeAdapter adapter;
  late Dio dio;

  void setUpLogger([
    NetworkLoggerConfig config = const NetworkLoggerConfig(
      consoleLogLevel: ConsoleLogLevel.none,
    ),
  ]) {
    netoscope = Netoscope(config: config);
    adapter = _FakeAdapter((_, __) async => _json({'ok': true}));
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(netoscope.dioInterceptor);
  }

  setUp(setUpLogger);
  tearDown(() => netoscope.dispose());

  test('records a successful call and leaves the response untouched', () async {
    adapter.handler = (_, __) async => _json({
          'user': {'id': 7, 'accessToken': 'real-token'},
        });

    final response = await dio.get<Map<String, dynamic>>(
      '/me',
      queryParameters: {'api_key': 'k', 'page': 1},
      options: Options(headers: {'Authorization': 'Bearer abc'}),
    );

    // The caller still receives the real data.
    expect(response.data!['user'], {'id': 7, 'accessToken': 'real-token'});

    final entry = netoscope.logs.single;
    expect(entry.method, 'GET');
    expect(entry.statusCode, 200);
    expect(entry.outcome, NetworkLogOutcome.success);
    expect(entry.duration, isNotNull);
    expect(entry.url.path, '/me');
    expect(entry.queryParameters, {
      'api_key': ['***'],
      'page': ['1'],
    });
    expect(entry.requestHeaders['Authorization'], '***');
    expect(entry.responseHeaders['content-type'], Headers.jsonContentType);
    expect(entry.responseBody!.kind, NetworkBodyKind.json);
    expect(
      entry.responseBody!.content,
      '{"user":{"id":7,"accessToken":"***"}}',
    );
  });

  test('redacts request bodies without mutating the sent data', () async {
    final payload = {'email': 'a@b.dev', 'password': 'hunter2'};
    String? sentBody;
    adapter.handler = (options, _) async {
      sentBody = jsonEncode(options.data);
      return _json({'refresh_token': 'r'});
    };

    await dio.post<void>('/login', data: payload);

    expect(payload['password'], 'hunter2');
    expect(sentBody, contains('hunter2'));
    final entry = netoscope.logs.single;
    expect(entry.requestBody!.content, '{"email":"a@b.dev","password":"***"}');
    expect(entry.responseBody!.content, '{"refresh_token":"***"}');
  });

  test('records HTTP errors and rethrows the original exception', () async {
    adapter.handler = (_, __) async => _json({'error': 'nope'}, status: 404);

    await expectLater(
      dio.get<void>('/missing'),
      throwsA(
        isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.badResponse)
            .having((e) => e.response?.statusCode, 'status', 404),
      ),
    );

    final entry = netoscope.logs.single;
    expect(entry.statusCode, 404);
    expect(entry.outcome, NetworkLogOutcome.httpError);
    expect(entry.error!.type, NetworkErrorType.badResponse);
    expect(entry.responseBody!.content, '{"error":"nope"}');
  });

  test('records timeouts', () async {
    adapter.handler = (options, _) async => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
          message: 'Receive timeout',
        );

    await expectLater(
      dio.get<void>('/slow'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    final entry = netoscope.logs.single;
    expect(entry.hasResponse, isFalse);
    expect(entry.outcome, NetworkLogOutcome.failure);
    expect(entry.error!.type, NetworkErrorType.timeout);
  });

  test('records connection failures', () async {
    adapter.handler = (options, _) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
        );

    await expectLater(dio.get<void>('/down'), throwsA(isA<DioException>()));

    final entry = netoscope.logs.single;
    expect(entry.error!.type, NetworkErrorType.connection);
    expect(entry.error!.message, contains('Connection refused'));
  });

  test('records cancelled calls', () async {
    final token = CancelToken();
    adapter.handler = (_, __) => Completer<ResponseBody>().future;

    final call = dio.get<void>('/pending', cancelToken: token);
    await pumpEventQueue();
    token.cancel('user left');

    await expectLater(
      call,
      throwsA(
        isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel),
      ),
    );
    expect(netoscope.logs.single.outcome, NetworkLogOutcome.cancelled);
  });

  test('keeps timings separate across concurrent calls', () async {
    final random = Random(1);
    adapter.handler = (options, _) async {
      await Future<void>.delayed(Duration(milliseconds: random.nextInt(20)));
      return _json({'n': options.queryParameters['n']});
    };

    await Future.wait([
      for (var i = 0; i < 25; i++)
        dio.get<void>('/items', queryParameters: {'n': i}),
    ]);

    final logs = netoscope.logs;
    expect(logs, hasLength(25));
    expect(logs.map((e) => e.id).toSet(), hasLength(25));
    for (final entry in logs) {
      final n = entry.queryParameters['n']!.single;
      expect(entry.responseBody!.content, '{"n":$n}');
      expect(entry.duration, isNotNull);
    }
  });

  test('does not consume streamed responses', () async {
    adapter.handler = (_, __) async => ResponseBody.fromString('streamed', 200);

    final response = await dio.get<ResponseBody>(
      '/download',
      options: Options(responseType: ResponseType.stream),
    );

    expect(netoscope.logs.single.responseBody!.kind, NetworkBodyKind.stream);
    final bytes = await response.data!.stream.expand((c) => c).toList();
    expect(utf8.decode(bytes), 'streamed');
  });

  test('describes multipart uploads without file contents', () async {
    await dio.post<void>(
      '/upload',
      data: FormData.fromMap({
        'name': 'ada',
        'password': 'pw',
        'file': MultipartFile.fromBytes(
          utf8.encode('file-secret'),
          filename: 'notes.txt',
        ),
      }),
    );

    final body = netoscope.logs.single.requestBody!;
    expect(body.kind, NetworkBodyKind.multipart);
    expect(body.content, isNot(contains('file-secret')));
    expect(body.content, isNot(contains('"pw"')));
    expect(body.content, contains('notes.txt'));
  });

  test('skips excluded URLs and opted-out requests', () async {
    setUpLogger(
      const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        excludedUrls: ['/health'],
      ),
    );

    await dio.get<void>('/health');
    await dio.get<void>(
      '/metrics',
      options: Options(extra: {Netoscope.skipLoggingKey: true}),
    );
    await dio.get<void>('/users');

    expect(netoscope.logs.map((e) => e.url.path), ['/users']);
  });

  test('respects header and body capture switches', () async {
    setUpLogger(
      const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        captureHeaders: false,
        captureRequestBody: false,
        captureResponseBody: false,
      ),
    );

    await dio.post<void>('/x', data: {'a': 1});

    final entry = netoscope.logs.single;
    expect(entry.requestHeaders, isEmpty);
    expect(entry.responseHeaders, isEmpty);
    expect(entry.requestBody, isNull);
    expect(entry.responseBody, isNull);
  });

  test('is a pass-through when logging is disabled', () async {
    setUpLogger(const NetworkLoggerConfig(enabled: false));

    final response = await dio.get<Map<String, dynamic>>('/x');

    expect(response.data, {'ok': true});
    expect(netoscope.logs, isEmpty);
  });
}
