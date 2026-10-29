// End-to-end check that secrets captured by any HTTP integration never reach
// an output: the store, console, notifications, cURL, JSON/HAR exports,
// persisted history or the inspector UI.
//
// Every secret value below contains the marker `LEAK`; nothing else does.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/data/export/curl_exporter.dart';
import 'package:netoscope/src/ui/screens/request_detail_screen.dart';

const _marker = 'LEAK';
const _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.LEAKsignature';

void _expectNoLeak(String where, String text) {
  expect(text, isNot(contains(_marker)), reason: 'secret leaked via $where');
}

class _RecordingNotifier implements NetworkActivityNotifier {
  final List<NetworkActivitySummary> shown = [];

  @override
  Future<void> show(NetworkActivitySummary summary) async => shown.add(summary);

  @override
  Future<void> hide() async {}
}

/// Answers every Dio request locally, echoing secrets back in responses.
class _DioBackend implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    if (options.uri.path == '/fail') {
      throw Exception(
        'connect failed: https://bob:LEAK-userinfo@api.dev/x?token=LEAK-q',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'name': 'Ada',
        'access_token': 'LEAK-access',
        'refresh_token': 'LEAK-refresh',
        'profile': {
          'session': {'id': 'LEAK-session'},
          'avatar': 'https://cdn.dev/a.png?token=LEAK-cdn',
        },
        'tokens': [
          {'id_token': _jwt},
        ],
        'raw': '{"client_secret":"LEAK-embedded"}',
        'trace': _jwt,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'set-cookie': ['sid=LEAK-cookie; HttpOnly'],
        'location': ['https://app.dev/cb#access_token=LEAK-fragment&ok=1'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Answers every `package:http` request locally.
class _HttpBackend extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().drain<void>();
    final (type, body) = switch (request.url.path) {
      '/text' => ('text/plain', 'password: LEAK-text\nstatus: ok'),
      '/cut' => (
          'application/json',
          '{"name": "Ada", "session": {"id": "LEAK-cut1", "data": "LEAK-cut2"',
        ),
      '/xml' => (
          'application/xml',
          '<user><name>Ada</name><password>LEAK-xml</password>'
              '<auth token="LEAK-attr"/></user>',
        ),
      _ => ('application/json', '{"ok":true}'),
    };
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': type},
    );
  }
}

void main() {
  late Netoscope netoscope;
  late _RecordingNotifier notifier;
  final console = <String>[];

  setUpAll(() async {
    notifier = _RecordingNotifier();
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        sensitiveHeaders: {'X-Customer-Ref'},
        sensitiveQueryParameters: {'ref'},
        sensitiveBodyKeys: {'national_id'},
      ),
      sinks: [
        ConsoleNetworkLogSink(
          level: ConsoleLogLevel.verbose,
          output: console.add,
        ),
      ],
      notifier: notifier,
      notificationInterval: Duration.zero,
    );

    final dio = Dio()
      ..httpClientAdapter = _DioBackend()
      ..interceptors.add(netoscope.dioInterceptor);

    // Secrets in the URL, path, fragment and headers.
    await dio.get<void>(
      'https://user:LEAK-pw@api.dev/verify/$_jwt',
      queryParameters: {
        'page': '2',
        'api_key': 'LEAK-apikey',
        'key': 'LEAK-google',
        'ref': 'LEAK-ref',
        'redirect': 'https://x.dev/?access_token=LEAK-nested',
        'variables': '{"password":"LEAK-gqlvar"}',
        'query': 'query Me { me { id } }',
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer LEAK-bearer',
          'Cookie': 'sid=LEAK-cookie',
          'X-Api-Key': 'LEAK-xapikey',
          'X-Upstream': 'Bearer LEAK-upstream',
          'X-Trace': _jwt,
          'X-Customer-Ref': 'LEAK-custom',
          'Accept': 'application/json',
        },
      ),
    );

    // Nested JSON with secrets, including JSON inside strings.
    await dio.post<void>(
      'https://api.dev/login',
      data: {
        'user': {
          'name': 'Ada',
          'password': 'LEAK-password',
          'national_id': 'LEAK-national',
          'devices': [
            {'id': 1, 'refresh_token': 'LEAK-device'},
          ],
        },
        'payload': '{"apiKey":"LEAK-payload","nested":{"pin":"LEAK-pin"}}',
        'note': 'Bearer LEAK-note',
      },
    );

    // Form body with a percent-encoded key.
    await dio.post<void>(
      'https://api.dev/oauth/token',
      data: 'grant_type=password&user%5Bpassword%5D=LEAK-form'
          '&client_secret=LEAK-form2&scope=read',
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    // Multipart: a sensitive field and a GraphQL `operations` field.
    await dio.post<void>(
      'https://api.dev/graphql',
      data: FormData.fromMap({
        'password': 'LEAK-field',
        'operations': jsonEncode({
          'query': r'mutation Up($file: Upload!, $token: String) '
              r'{ up(file: $file, token: $token) }',
          'variables': {'file': null, 'token': 'LEAK-ops'},
        }),
        'file': MultipartFile.fromString('data', filename: 'a.txt'),
      }),
    );

    // GraphQL document with a literal secret argument.
    await dio.post<void>(
      'https://api.dev/graphql',
      data: {
        'query': 'mutation { login(email: "ada@x.dev", password: "LEAK-lit") '
            '{ token } }',
      },
    );

    // Failure whose message contains credentials.
    try {
      await dio.get<void>('https://api.dev/fail');
    } on DioException {
      // Expected.
    }

    final client = netoscope.httpClient(_HttpBackend());
    await client.post(
      Uri.parse('https://api.dev/signup?ref=LEAK-ref2'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': 'ada@x.dev', 'newPassword': 'LEAK-new'}),
    );
    await client.get(Uri.parse('https://api.dev/text'));
    await client.get(Uri.parse('https://api.dev/cut'));
    await client.get(Uri.parse('https://api.dev/xml'));
    final multipart =
        http.MultipartRequest('POST', Uri.parse('https://api.dev/upload'))
          ..fields['meta'] = '{"title":"cv","access_token":"LEAK-meta"}'
          ..fields['secret'] = 'LEAK-plainfield';
    await (await client.send(multipart)).stream.drain<void>();
    client.close();

    netoscope.recordExternalCall(
      ExternalNetworkCall(
        method: 'POST',
        url: Uri.parse('https://native.dev/x?token=LEAK-native'),
        startedAt: DateTime.utc(2026),
        requestHeaders: const {'authorization': 'Basic LEAK-basic'},
        requestBody: '{"password":"LEAK-native-body"}',
        statusCode: 200,
        responseHeaders: const {'content-type': 'application/json'},
        responseBody: '{"refreshToken":"LEAK-native-res"}',
        source: 'android',
      ),
    );

    // Let the notification controller push.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  tearDownAll(() => netoscope.dispose());

  test('all calls were recorded and keep their non-secret data', () {
    expect(netoscope.logs, hasLength(12));
    final json = netoscope.exportJson();
    for (final kept in [
      'Ada',
      'page=2',
      'grant_type=password',
      'scope=read',
      'application/json',
      'mutation Up',
      'cv',
      'status: ok',
    ]) {
      expect(json, contains(kept), reason: kept);
    }
  });

  test('stored entries contain no secrets', () {
    for (final entry in netoscope.logs) {
      _expectNoLeak('entry ${entry.url}', jsonEncode(entry.toJson()));
      _expectNoLeak('details ${entry.url}', entry.details.toString());
      for (final details in entry.details) {
        _expectNoLeak('details ${entry.url}', details.describe().toString());
      }
    }
  });

  test('exports contain no secrets', () {
    _expectNoLeak('JSON export', netoscope.exportJson());
    _expectNoLeak('HAR export', netoscope.exportHar());
  });

  test('cURL commands contain no secrets', () {
    var built = 0;
    for (final entry in netoscope.logs) {
      final curl = buildCurlCommand(entry);
      if (curl == null) continue;
      built++;
      _expectNoLeak('cURL ${entry.url}', curl.command);
    }
    expect(built, netoscope.logs.length);
  });

  test('console output contains no secrets', () {
    expect(console, hasLength(netoscope.logs.length));
    _expectNoLeak('console', console.join('\n'));
  });

  test('notifications contain no secrets', () {
    expect(notifier.shown, isNotEmpty);
    for (final summary in notifier.shown) {
      _expectNoLeak(
        'notification',
        [summary.title, summary.body, ...summary.lines].join('\n'),
      );
    }
  });

  test('persisted history contains no secrets', () async {
    final dir = await Directory.systemTemp.createTemp('netoscope_leak');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/history.json';
    await FileNetworkLogPersistence(path).save(netoscope.logs);
    _expectNoLeak('persistence', await File(path).readAsString());
  });

  testWidgets('the inspector shows no secrets', (tester) async {
    String visibleText() => [
          for (final text in tester.widgetList<RichText>(find.byType(RichText)))
            text.text.toPlainText(),
          for (final field
              in tester.widgetList<EditableText>(find.byType(EditableText)))
            field.controller.text,
        ].join('\n');

    await tester.pumpWidget(
      MaterialApp(home: NetworkInspector(netoscope: netoscope)),
    );
    await tester.pumpAndSettle();
    _expectNoLeak('request list', visibleText());

    for (final entry in netoscope.logs) {
      await tester.pumpWidget(
        MaterialApp(home: RequestDetailScreen(entry: entry)),
      );
      await tester.pumpAndSettle();
      final tabs = find.descendant(
        of: find.byType(TabBar),
        matching: find.byType(Tab),
      );
      for (var i = 0; i < tabs.evaluate().length; i++) {
        await tester.tap(tabs.at(i));
        await tester.pumpAndSettle();
        _expectNoLeak('detail ${entry.url} tab $i', visibleText());
      }
    }
  });
}
