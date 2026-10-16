import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netoscope/netoscope.dart';

class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString('{}', 200);

  @override
  void close({bool force = false}) {}
}

void main() {
  late Netoscope netoscope;
  late Dio dio;
  late http.Client client;

  setUp(() {
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    dio = Dio()
      ..httpClientAdapter = _OkAdapter()
      ..interceptors.add(netoscope.dioInterceptor);
    client =
        netoscope.httpClient(MockClient((_) async => http.Response('', 200)));
  });

  Map<String, List<String>> tagsByPath() => {
        for (final e in netoscope.logs) e.url.path: e.tags,
      };

  test('global tags apply until removed', () async {
    netoscope.addTag('checkout');
    expect(netoscope.activeTags, {'checkout'});
    await dio.get<void>('https://a.dev/cart');
    netoscope.removeTag('checkout');
    await dio.get<void>('https://a.dev/after');

    expect(tagsByPath(), {
      '/cart': ['checkout'],
      '/after': <String>[],
    });
  });

  test('tagged() covers async work across clients and nests', () async {
    await netoscope.tagged('login-flow', () async {
      await dio.get<void>('https://a.dev/login');
      await Future<void>.delayed(Duration.zero);
      await client.get(Uri.parse('https://a.dev/profile'));
      await netoscope.tagged(['mfa'], () => dio.get<void>('https://a.dev/otp'));
    });
    await dio.get<void>('https://a.dev/outside');

    expect(tagsByPath(), {
      '/login': ['login-flow'],
      '/profile': ['login-flow'],
      '/otp': unorderedEquals(['login-flow', 'mfa']),
      '/outside': <String>[],
    });
  });

  test('per-request Dio tags combine with others', () async {
    netoscope.addTag('global');
    await dio.get<void>(
      'https://a.dev/x',
      options: Options(extra: {
        Netoscope.tagsKey: ['a', 'b']
      }),
    );
    expect(netoscope.logs.single.tags, unorderedEquals(['global', 'a', 'b']));
    expect(netoscope.logs.single.toJson()['tags'], isNotEmpty);
  });

  test('recordExternalCall redacts and inspects like captured calls', () {
    netoscope.recordExternalCall(
      ExternalNetworkCall(
        method: 'POST',
        url: Uri.parse('https://api.dev/graphql?api_key=k'),
        startedAt: DateTime.utc(2026),
        duration: const Duration(milliseconds: 80),
        requestHeaders: const {
          'Authorization': 'Bearer t',
          'Content-Type': 'application/json',
        },
        requestBody: '{"query":"query Me { me { id } }"}',
        statusCode: 200,
        responseHeaders: const {'content-type': 'application/json'},
        responseBody: '{"data":{"me":{"id":1}},"token":"x"}',
        source: 'android',
        tags: const ['native'],
      ),
    );

    final entry = netoscope.logs.single;
    expect(entry.queryParameters['api_key'], ['***']);
    expect(entry.requestHeaders['Authorization'], '***');
    expect(
        entry.responseBody!.content, '{"data":{"me":{"id":1}},"token":"***"}');
    expect(entry.graphQL!.operations.single.name, 'Me');
    expect(entry.metadata['source'], 'android');
    expect(entry.tags, ['native']);
    expect(entry.responseSize, 36);
  });

  test('external failures keep their error type', () {
    netoscope.recordExternalCall(
      ExternalNetworkCall(
        method: 'GET',
        url: Uri.parse('https://api.dev/x'),
        startedAt: DateTime.utc(2026),
        error: 'timeout after 10s',
        errorType: NetworkErrorType.timeout,
      ),
    );
    expect(netoscope.logs.single.error!.type, NetworkErrorType.timeout);
    expect(netoscope.logs.single.outcome, NetworkLogOutcome.failure);
  });
}
