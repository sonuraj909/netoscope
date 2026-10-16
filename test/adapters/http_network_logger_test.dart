import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netoscope/netoscope.dart';

const _quiet = NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none);

void main() {
  late Netoscope netoscope;

  setUp(() => netoscope = Netoscope(config: _quiet));
  tearDown(() => netoscope.dispose());

  http.Client clientFor(MockClientHandler handler) =>
      netoscope.httpClient(MockClient(handler));

  test('records a successful call; the caller reads the full body', () async {
    final client = clientFor(
      (request) async => http.Response(
        '{"id":1,"token":"real"}',
        200,
        headers: {'content-type': 'application/json', 'set-cookie': 'sid=1'},
      ),
    );

    final response = await client.post(
      Uri.parse('https://api.example.com/login?otp=123&lang=en'),
      headers: {'content-type': 'application/json', 'x-api-key': 'k'},
      body: jsonEncode({'user': 'ada', 'password': 'pw'}),
    );

    expect(response.body, '{"id":1,"token":"real"}');
    final entry = netoscope.logs.single;
    expect(entry.method, 'POST');
    expect(entry.statusCode, 200);
    expect(entry.duration, isNotNull);
    expect(entry.queryParameters['otp'], ['***']);
    expect(entry.queryParameters['lang'], ['en']);
    expect(entry.requestHeaders['x-api-key'], '***');
    expect(entry.responseHeaders['set-cookie'], '***');
    expect(entry.requestBody!.content, '{"user":"ada","password":"***"}');
    expect(entry.responseBody!.content, '{"id":1,"token":"***"}');
    expect(entry.responseSize, 23);
  });

  test('HTTP error statuses are recorded without throwing', () async {
    final client = clientFor((_) async => http.Response('boom', 503));

    final response = await client.get(Uri.parse('https://api.example.com/x'));

    expect(response.statusCode, 503);
    expect(netoscope.logs.single.outcome, NetworkLogOutcome.httpError);
    expect(netoscope.logs.single.responseBody!.content, 'boom');
  });

  test('connection failures are recorded and rethrown unchanged', () async {
    final failure = http.ClientException('Connection refused');
    final client = clientFor((_) async => throw failure);

    await expectLater(
      client.get(Uri.parse('https://api.example.com/x')),
      throwsA(same(failure)),
    );

    final entry = netoscope.logs.single;
    expect(entry.hasResponse, isFalse);
    expect(entry.error!.type, NetworkErrorType.connection);
  });

  test('timeouts raised by the inner client are recorded', () async {
    final client = clientFor((_) async => throw TimeoutException('too slow'));

    await expectLater(
      client.get(Uri.parse('https://api.example.com/x')),
      throwsA(isA<TimeoutException>()),
    );
    expect(netoscope.logs.single.error!.type, NetworkErrorType.timeout);
  });

  test('aborted requests are recorded as cancelled', () async {
    final url = Uri.parse('https://api.example.com/x');
    final client =
        clientFor((_) async => throw http.RequestAbortedException(url));

    await expectLater(
        client.get(url), throwsA(isA<http.RequestAbortedException>()));
    expect(netoscope.logs.single.outcome, NetworkLogOutcome.cancelled);
  });

  group('streamed responses', () {
    test('are recorded only once the caller has read them', () async {
      final controller = StreamController<List<int>>();
      final client = netoscope.httpClient(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(controller.stream, 200),
        ),
      );

      final response =
          await client.send(http.Request('GET', Uri.parse('https://a.dev/s')));
      expect(netoscope.logs, isEmpty);

      final body = response.stream.bytesToString();
      controller
        ..add(utf8.encode('chunk-1 '))
        ..add(utf8.encode('chunk-2'));
      await controller.close();

      expect(await body, 'chunk-1 chunk-2');
      final entry = netoscope.logs.single;
      expect(entry.responseBody!.content, 'chunk-1 chunk-2');
      expect(entry.responseSize, 15);
    });

    test('a cancelled read records a truncated body', () async {
      final client = netoscope.httpClient(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            Stream.fromIterable([utf8.encode('first'), utf8.encode('second')]),
            200,
            headers: {'content-type': 'text/plain'},
          ),
        ),
      );

      final response =
          await client.send(http.Request('GET', Uri.parse('https://a.dev/s')));
      await response.stream.first;

      final body = netoscope.logs.single.responseBody!;
      expect(body.content, 'first');
      expect(body.isTruncated, isTrue);
    });

    test('errors in the body stream reach the caller and are recorded',
        () async {
      final client = netoscope.httpClient(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            Stream<List<int>>.error(http.ClientException('reset')),
            200,
          ),
        ),
      );

      final response =
          await client.send(http.Request('GET', Uri.parse('https://a.dev/s')));
      await expectLater(
        response.stream.toBytes(),
        throwsA(isA<http.ClientException>()),
      );
      expect(netoscope.logs.single.error!.type, NetworkErrorType.connection);
    });
  });

  test('binary responses are not decoded', () async {
    final client = clientFor(
      (_) async => http.Response.bytes(
        [0x89, 0x50, 0x4e, 0x47],
        200,
        headers: {'content-type': 'image/png'},
      ),
    );

    await client.get(Uri.parse('https://a.dev/logo.png'));

    expect(netoscope.logs.single.responseBody!.content, '<binary, 4 bytes>');
  });

  test('large bodies are truncated to maxBodySize', () async {
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        maxBodySize: 10,
      ),
    );
    final client = clientFor((_) async => http.Response('x' * 100, 200));

    final response = await client.get(Uri.parse('https://a.dev/big'));

    expect(response.body, hasLength(100));
    final body = netoscope.logs.single.responseBody!;
    expect(body.content, 'x' * 10);
    expect(body.isTruncated, isTrue);
  });

  test('multipart requests describe files without their contents', () async {
    final client = clientFor((_) async => http.Response('', 201));
    final request =
        http.MultipartRequest('POST', Uri.parse('https://a.dev/upload'))
          ..fields['title'] = 'hello'
          ..fields['api_key'] = 'k'
          ..files.add(
            http.MultipartFile.fromString(
              'doc',
              'file-secret',
              filename: 'a.txt',
            ),
          );

    await (await client.send(request)).stream.drain<void>();

    final body = netoscope.logs.single.requestBody!;
    expect(body.kind, NetworkBodyKind.multipart);
    expect(body.content, contains('a.txt'));
    expect(body.content, isNot(contains('file-secret')));
    expect(body.content, contains('"value":"***"'));
  });

  test('streamed request bodies are not read', () async {
    final client = clientFor((request) async {
      // The inner client still receives the whole body.
      return http.Response(request.body, 200);
    });
    final request = http.StreamedRequest('PUT', Uri.parse('https://a.dev/u'));
    request.sink.add(utf8.encode('payload'));
    unawaited(request.sink.close());

    final response = await http.Response.fromStream(await client.send(request));

    expect(response.body, 'payload');
    expect(netoscope.logs.single.requestBody!.kind, NetworkBodyKind.stream);
  });

  test('concurrent calls are recorded independently', () async {
    final random = Random(3);
    final client = clientFor((request) async {
      await Future<void>.delayed(Duration(milliseconds: random.nextInt(15)));
      return http.Response(request.url.queryParameters['n']!, 200);
    });

    await Future.wait([
      for (var i = 0; i < 20; i++)
        client.get(Uri.parse('https://a.dev/items?n=$i')),
    ]);

    expect(netoscope.logs, hasLength(20));
    for (final entry in netoscope.logs) {
      expect(entry.responseBody!.content, entry.queryParameters['n']!.single);
    }
  });

  test('excluded URLs are passed through without logging', () async {
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        excludedUrls: ['/health'],
      ),
    );
    final client = clientFor((_) async => http.Response('ok', 200));

    await client.get(Uri.parse('https://a.dev/health'));

    expect(netoscope.logs, isEmpty);
  });

  test('returns the inner client unwrapped when disabled', () {
    final inner = MockClient((_) async => http.Response('', 200));
    final disabled =
        Netoscope(config: const NetworkLoggerConfig(enabled: false));
    expect(disabled.httpClient(inner), same(inner));
  });
}
