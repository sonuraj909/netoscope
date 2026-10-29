// Uses real loopback sockets. Plain `test`s only: the widget-test binding
// replaces HttpOverrides with a mock.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:netoscope/netoscope.dart';

const _quiet = NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none);

/// An app-level override installed after capture, delegating to the
/// overrides that were current when it was created.
class _LaterOverrides extends HttpOverrides {
  _LaterOverrides() : _previous = HttpOverrides.current;

  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _previous?.createHttpClient(context) ?? super.createHttpClient(context);
}

class _PreviousOverrides extends HttpOverrides {
  int created = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    return super.createHttpClient(context);
  }
}

void main() {
  late HttpServer server;
  late Uri base;
  late Netoscope netoscope;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final response = request.response;
      switch (request.uri.path) {
        case '/json':
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'name': 'Ada', 'token': 'secret-1'}));
        case '/echo':
          response.headers.contentType = ContentType.json;
          response.write(body);
        case '/error':
          response.statusCode = 500;
          response.write('boom');
        case '/image':
          response.headers.contentType = ContentType('image', 'png');
          response.add(List.filled(4096, 7));
        case '/events':
          response.headers.contentType = ContentType('text', 'event-stream');
          response.write('event: tick\ndata: 1\n\ndata: 2\n\n');
        default:
          response.statusCode = 404;
      }
      await response.close();
    });
    netoscope = Netoscope(config: _quiet);
  });

  tearDown(() async {
    await netoscope.dispose();
    await server.close(force: true);
  });

  Future<String> read(HttpClientResponse response) =>
      utf8.decoder.bind(response).join();

  test('records HttpClient calls and leaves the data untouched', () async {
    expect(netoscope.captureDartIo(), isTrue);
    final client = HttpClient();
    final request = await client.getUrl(base.replace(path: '/json'));
    request.headers.set('authorization', 'Bearer abc');
    final response = await request.close();

    expect(await read(response), '{"name":"Ada","token":"secret-1"}');
    client.close();

    final entry = netoscope.logs.single;
    expect(entry.method, 'GET');
    expect(entry.statusCode, 200);
    expect(entry.duration, isNotNull);
    expect(entry.requestHeaders['authorization'], '***');
    expect(entry.responseBody!.content, '{"name":"Ada","token":"***"}');
    expect(entry.responseSize, 33);
  });

  test('captures written request bodies with redaction', () async {
    netoscope.captureDartIo();
    final client = HttpClient();
    final request = await client.postUrl(base.replace(path: '/echo'));
    request.headers.contentType = ContentType.json;
    request.write('{"user":"ada",');
    request.add(utf8.encode('"password":"pw"}'));
    final echoed = await read(await request.close());
    client.close();

    expect(echoed, '{"user":"ada","password":"pw"}');
    final entry = netoscope.logs.single;
    expect(entry.requestBody!.content, '{"user":"ada","password":"***"}');
    expect(entry.requestSize, 30);
  });

  test('records HTTP errors and connection failures', () async {
    netoscope.captureDartIo();
    final client = HttpClient();
    await read(
        await (await client.getUrl(base.replace(path: '/error'))).close());
    expect(netoscope.logs.single.outcome, NetworkLogOutcome.httpError);

    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    await expectLater(
      client.getUrl(Uri.parse('http://127.0.0.1:$port/x')),
      throwsA(isA<SocketException>()),
    );
    client.close();

    final failure = netoscope.logs.first;
    expect(failure.hasResponse, isFalse);
    expect(failure.error!.type, NetworkErrorType.connection);
  });

  test('media responses are counted, not buffered', () async {
    netoscope.captureDartIo();
    final client = HttpClient();
    final response =
        await (await client.getUrl(base.replace(path: '/image'))).close();
    final bytes = await response.fold<int>(0, (n, chunk) => n + chunk.length);
    client.close();

    expect(bytes, 4096);
    final body = netoscope.logs.single.responseBody!;
    expect(body.kind, NetworkBodyKind.binary);
    expect(body.content, '<binary, 4096 bytes>');
  });

  test('event streams are recorded as SSE', () async {
    netoscope.captureDartIo();
    final client = HttpClient();
    final response =
        await (await client.getUrl(base.replace(path: '/events'))).close();
    await read(response);
    client.close();

    final logs = netoscope.logs.reversed.toList();
    expect(logs.map((e) => e.protocol).toSet(), {NetworkProtocol.sse});
    expect(
      logs.where((e) => e.kind == NetworkEventKind.message).length,
      2,
    );
  });

  test('calls recorded by the http or Dio integrations are not doubled',
      () async {
    netoscope.captureDartIo();

    // package:http's default client is an IOClient over dart:io.
    final client = netoscope.httpClient();
    await client.get(base.replace(path: '/json'));
    client.close();

    // Dio's default adapter also uses dart:io.
    final dio = Dio()..interceptors.add(netoscope.dioInterceptor);
    await dio.get<void>(base.replace(path: '/json').toString());
    dio.close();

    // A raw HttpClient call is still recorded.
    final raw = HttpClient();
    await read(await (await raw.getUrl(base.replace(path: '/json'))).close());
    raw.close();

    expect(netoscope.logs, hasLength(3));
  });

  test('chains previous HttpOverrides and restores them', () async {
    final previous = _PreviousOverrides();
    HttpOverrides.global = previous;
    addTearDown(() => HttpOverrides.global = null);

    netoscope.captureDartIo();
    expect(netoscope.isCapturingDartIo, isTrue);
    final client = HttpClient();
    await read(
        await (await client.getUrl(base.replace(path: '/json'))).close());
    client.close();
    expect(previous.created, 1, reason: 'the previous overrides still apply');
    expect(netoscope.logs, hasLength(1));

    netoscope.stopCapturingDartIo();
    expect(HttpOverrides.current, same(previous));
    final after = HttpClient();
    await read(await (await after.getUrl(base.replace(path: '/json'))).close());
    after.close();
    expect(netoscope.logs, hasLength(1), reason: 'no longer captured');
  });

  test('respects exclusions, pausing and disabled builds', () async {
    final excluded = Netoscope(
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        excludedUrls: ['/json'],
      ),
    )..captureDartIo();
    final client = HttpClient();
    await read(
        await (await client.getUrl(base.replace(path: '/json'))).close());
    expect(excluded.logs, isEmpty);
    await excluded.dispose();

    netoscope
      ..captureDartIo()
      ..setLoggingEnabled(false);
    final paused = HttpClient();
    await read(
        await (await paused.getUrl(base.replace(path: '/json'))).close());
    paused.close();
    client.close();
    expect(netoscope.logs, isEmpty);

    final disabled =
        Netoscope(config: const NetworkLoggerConfig(enabled: false));
    expect(disabled.captureDartIo(), isFalse);
  });
  test('captures package:http and Dio without their integrations', () async {
    netoscope.captureDartIo();

    // The top-level functions use http.Client(), an IOClient on the VM.
    final response = await http.get(base.replace(path: '/json'));
    expect(response.body, '{"name":"Ada","token":"secret-1"}');

    // Dio's default IOHttpClientAdapter, with no Netoscope interceptor.
    final dio = Dio();
    final dioResponse = await dio.post<Map<String, dynamic>>(
      base.replace(path: '/echo').toString(),
      data: {'user': 'ada', 'password': 'pw'},
    );
    expect(dioResponse.data, {'user': 'ada', 'password': 'pw'});
    dio.close();

    final logs = netoscope.logs;
    expect(logs, hasLength(2), reason: 'each call is recorded exactly once');
    expect(logs.first.method, 'POST');
    expect(logs.first.requestBody!.content, '{"user":"ada","password":"***"}');
    expect(logs.last.responseBody!.content, '{"name":"Ada","token":"***"}');
  });

  test('integrations stay single when combined with capture', () async {
    netoscope.captureDartIo();
    final dio = Dio()..interceptors.add(netoscope.dioInterceptor);
    final client = netoscope.httpClient();

    // Concurrent calls to the same endpoint through every path.
    final raw = HttpClient();
    await Future.wait([
      dio.get<void>(base.replace(path: '/json').toString()),
      client.get(base.replace(path: '/json')),
      dio.post<void>(base.replace(path: '/echo').toString(), data: '{}'),
      client.post(base.replace(path: '/echo'), body: '{}'),
      raw
          .getUrl(base.replace(path: '/image'))
          .then((request) => request.close())
          .then(read),
    ]);
    dio.close();
    client.close();
    raw.close();

    expect(netoscope.logs, hasLength(5));
  });

  test('redacts URLs of raw HttpClient calls', () async {
    netoscope.captureDartIo();
    final client = HttpClient();
    final url = base.replace(
      path: '/json',
      queryParameters: {'access_token': 'a1', 'key': 'k1', 'page': '2'},
    );
    await read(await (await client.getUrl(url)).close());
    client.close();

    final logged = netoscope.logs.single.url;
    expect(logged.queryParameters, {
      'access_token': '***',
      'key': '***',
      'page': '2',
    });
  });

  test('stopping capture under a later app override passes through', () async {
    netoscope.captureDartIo();
    final later = _LaterOverrides();
    HttpOverrides.global = later;
    addTearDown(() => HttpOverrides.global = null);

    final before = HttpClient();
    await read(
        await (await before.getUrl(base.replace(path: '/json'))).close());
    before.close();
    expect(netoscope.logs, hasLength(1), reason: 'the app override delegates');

    netoscope.stopCapturingDartIo();
    expect(HttpOverrides.current, same(later), reason: 'not replaced');
    final after = HttpClient();
    await read(await (await after.getUrl(base.replace(path: '/json'))).close());
    after.close();
    expect(netoscope.logs, hasLength(1), reason: 'stopped despite the chain');
  });
}
