import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
// material.dart is deprecated from Flutter 3.47 (use package:material_ui);
// kept until the minimum supported Flutter version reaches 3.47.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netoscope/netoscope.dart';

const _replayable = NetworkLoggerConfig(
  consoleLogLevel: ConsoleLogLevel.none,
  enableReplay: true,
);

/// Records what reaches the transport.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<String> bodies = [];
  int status = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((chunk) => chunk).toList();
    bodies.add(utf8.decode(bytes));
    return ResponseBody.fromString(
      '{"ok":true}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Netoscope netoscope;
  late _RecordingAdapter adapter;
  late Dio dio;

  void setUpDio([NetworkLoggerConfig config = _replayable]) {
    netoscope = Netoscope(config: config);
    adapter = _RecordingAdapter();
    dio = netoscope.attachDio(
      Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter,
    );
  }

  tearDown(() => netoscope.dispose());

  group('Dio', () {
    test('is off by default', () async {
      setUpDio(
          const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none));
      await dio.get<Object?>('/me');
      final entry = netoscope.logs.single;
      expect(netoscope.canReplay(entry), isFalse);
      expect(() => netoscope.replay(entry), throwsStateError);
    });

    test('sends the original, unredacted request again', () async {
      setUpDio();
      await dio.post<Object?>(
        '/login',
        queryParameters: {'api_key': 'real-key'},
        data: {'user': 'ada', 'password': 'real-password'},
        options: Options(headers: {'Authorization': 'Bearer real-token'}),
      );
      final original = netoscope.logs.single;
      // The history itself stays redacted.
      expect(jsonEncode(original.toJson()), isNot(contains('real-')));
      expect(netoscope.canReplay(original), isTrue);

      await netoscope.replay(original);

      expect(adapter.requests, hasLength(2));
      final replayed = adapter.requests.last;
      expect(replayed.method, 'POST');
      expect(replayed.uri.queryParameters['api_key'], 'real-key');
      expect(replayed.headers['Authorization'], 'Bearer real-token');
      expect(adapter.bodies.last, contains('real-password'));

      final newest = netoscope.logs.first;
      expect(newest.id, isNot(original.id));
      expect(newest.tags, contains('replay'));
      expect(jsonEncode(newest.toJson()), isNot(contains('real-')));
    });

    test('runs the app interceptors again', () async {
      setUpDio();
      var calls = 0;
      dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.next(options);
          },
        ),
      );
      await dio.get<Object?>('/items');
      await netoscope.replay(netoscope.logs.single);
      expect(calls, 2);
    });

    test('a failing replay completes and is recorded', () async {
      setUpDio();
      await dio.get<Object?>('/flaky');
      adapter.status = 503;
      await netoscope.replay(netoscope.logs.single);
      expect(netoscope.logs.first.statusCode, 503);
    });

    test('does not reuse the cancel token or progress callbacks', () async {
      setUpDio();
      final token = CancelToken();
      var progress = 0;
      await dio.get<Object?>(
        '/download',
        cancelToken: token,
        onReceiveProgress: (_, __) => progress++,
      );
      token.cancel();
      final before = progress;

      await netoscope.replay(netoscope.logs.single);
      expect(adapter.requests, hasLength(2));
      expect(progress, before);
    });

    test('replays multipart uploads', () async {
      setUpDio();
      await dio.post<Object?>(
        '/upload',
        data: FormData.fromMap({
          'name': 'avatar',
          'file': MultipartFile.fromBytes([1, 2, 3], filename: 'a.png'),
        }),
      );
      await netoscope.replay(netoscope.logs.single);
      expect(adapter.requests, hasLength(2));
      expect(adapter.bodies.last, contains('avatar'));
    });

    test('the shared interceptor replays with a plain Dio', () async {
      netoscope = Netoscope(config: _replayable);
      adapter = _RecordingAdapter();
      dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(netoscope.dioInterceptor);
      await dio.get<Object?>('https://api.example.com/me');
      expect(netoscope.canReplay(netoscope.logs.single), isTrue);
    });

    test('clearing the history forgets replayable requests', () async {
      setUpDio();
      await dio.get<Object?>('/me');
      final entry = netoscope.logs.single;
      netoscope.clearLogs();
      expect(netoscope.canReplay(entry), isFalse);
    });

    test('keeps at most maxHistorySize replayable requests', () async {
      setUpDio(
        const NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
          enableReplay: true,
          maxHistorySize: 2,
        ),
      );
      await dio.get<Object?>('/1');
      final first = netoscope.logs.single;
      await dio.get<Object?>('/2');
      await dio.get<Object?>('/3');
      expect(netoscope.canReplay(first), isFalse);
      expect(netoscope.canReplay(netoscope.logs.first), isTrue);
    });
  });

  group('package:http', () {
    test('replays buffered requests through the same client', () async {
      netoscope = Netoscope(config: _replayable);
      final received = <http.Request>[];
      final client = netoscope.httpClient(
        MockClient((request) async {
          received.add(request);
          return http.Response('{}', 200);
        }),
      );
      await client.put(
        Uri.parse('https://api.example.com/profile?token=real-token'),
        headers: {'x-api-key': 'real-key'},
        body: '{"password":"real-password"}',
      );

      await netoscope.replay(netoscope.logs.single);

      expect(received, hasLength(2));
      expect(received.last.method, 'PUT');
      expect(received.last.headers['x-api-key'], 'real-key');
      expect(received.last.url.queryParameters['token'], 'real-token');
      expect(received.last.body, '{"password":"real-password"}');
      expect(netoscope.logs, hasLength(2));
      expect(netoscope.logs.first.tags, contains('replay'));
    });

    test('streamed requests cannot be replayed', () async {
      netoscope = Netoscope(config: _replayable);
      final client = netoscope.httpClient(
        MockClient.streaming((request, body) async {
          await body.drain<void>();
          return http.StreamedResponse(const Stream.empty(), 200);
        }),
      );
      final request = http.StreamedRequest(
        'POST',
        Uri.parse('https://api.example.com/stream'),
      );
      final sent = client.send(request);
      await request.sink.close();
      await (await sent).stream.drain<void>();
      expect(netoscope.canReplay(netoscope.logs.single), isFalse);
    });
  });

  group('inspector', () {
    Future<void> openDetail(WidgetTester tester, String path) async {
      await tester.pumpWidget(
        MaterialApp(home: NetworkInspector(netoscope: netoscope)),
      );
      await tester.tap(find.text(path));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
    }

    testWidgets('sends a GET again from the detail screen', (tester) async {
      await tester.runAsync(() async {
        setUpDio();
        await dio.get<Object?>('/me');
      });
      await openDetail(tester, '/me');

      await tester.runAsync(() async {
        await tester.tap(find.text('Send again'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(adapter.requests, hasLength(2));
      expect(find.textContaining('Sent again'), findsOneWidget);
    });

    testWidgets('asks before sending a POST again', (tester) async {
      await tester.runAsync(() async {
        setUpDio();
        await dio.post<Object?>('/orders', data: {'qty': 1});
      });
      await openDetail(tester, '/orders');
      await tester.tap(find.text('Send again'));
      await tester.pumpAndSettle();

      expect(find.text('Send this POST again?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(adapter.requests, hasLength(1));
    });

    testWidgets('offers no replay when it is off', (tester) async {
      await tester.runAsync(() async {
        setUpDio(
          const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
        );
        await dio.get<Object?>('/only');
      });
      await tester.pumpWidget(
        MaterialApp(home: NetworkInspector(netoscope: netoscope)),
      );
      await tester.tap(find.text('/only'));
      await tester.pumpAndSettle();
      // A single call has nothing to compare with and cannot be replayed.
      expect(find.byTooltip('More actions'), findsNothing);
    });
  });
}
