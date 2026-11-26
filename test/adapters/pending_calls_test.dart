import 'dart:async';
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
import 'package:netoscope/src/ui/network_log_filter.dart';

const _quiet = NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none);

/// A Dio transport whose responses are released by the test.
class _GatedAdapter implements HttpClientAdapter {
  final List<Completer<ResponseBody>> pending = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final completer = Completer<ResponseBody>();
    pending.add(completer);
    return completer.future;
  }

  void respond([int status = 200]) =>
      pending.removeAt(0).complete(ResponseBody.fromString('{}', status));

  void fail() => pending.removeAt(0).completeError(
        const SocketExceptionLike('connection reset'),
      );

  @override
  void close({bool force = false}) {}
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => message;
}

void main() {
  late Netoscope netoscope;

  tearDown(() => netoscope.dispose());

  group('Dio', () {
    late _GatedAdapter adapter;
    late Dio dio;

    void setUpDio([NetworkLoggerConfig config = _quiet]) {
      netoscope = Netoscope(config: config);
      adapter = _GatedAdapter();
      dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter
        ..interceptors.add(netoscope.dioInterceptor);
    }

    test('tracks a call until it finishes, then records it', () async {
      setUpDio();
      final changes = <int>[];
      netoscope.pendingChanges.listen((calls) => changes.add(calls.length));

      final future = dio.get<Object?>('/users', queryParameters: {'page': 2});
      await pumpEventQueue();

      final pending = netoscope.pendingCalls.single;
      expect(pending.method, 'GET');
      expect(pending.url.path, '/users');
      expect(pending.elapsed, greaterThanOrEqualTo(Duration.zero));
      expect(netoscope.logs, isEmpty);

      adapter.respond();
      await future;

      expect(netoscope.pendingCalls, isEmpty);
      expect(netoscope.logs.single.id, pending.id);
      expect(changes, [1, 0]);
    });

    test('lists concurrent calls newest first', () async {
      setUpDio();
      final first = dio.get<Object?>('/a');
      await pumpEventQueue();
      final second = dio.get<Object?>('/b');
      await pumpEventQueue();

      expect(netoscope.pendingCalls.map((c) => c.url.path), ['/b', '/a']);

      adapter
        ..respond()
        ..respond();
      await Future.wait([first, second]);
      expect(netoscope.pendingCalls, isEmpty);
    });

    test('ends tracking when the call fails', () async {
      setUpDio();
      final future = dio.get<Object?>('/down');
      await pumpEventQueue();
      expect(netoscope.pendingCalls, hasLength(1));

      adapter.fail();
      await expectLater(future, throwsA(isA<DioException>()));
      expect(netoscope.pendingCalls, isEmpty);
      expect(netoscope.logs.single.outcome, NetworkLogOutcome.failure);
    });

    test('ends tracking for HTTP error statuses', () async {
      setUpDio();
      final future = dio.get<Object?>('/missing');
      await pumpEventQueue();
      adapter.respond(404);
      await expectLater(future, throwsA(isA<DioException>()));
      expect(netoscope.pendingCalls, isEmpty);
    });

    test('redacts the pending URL', () async {
      setUpDio();
      final future = dio.get<Object?>(
        '/me',
        queryParameters: {'api_key': 'secret-key', 'page': 1},
      );
      await pumpEventQueue();

      final url = netoscope.pendingCalls.single.url;
      expect(url.toString(), isNot(contains('secret-key')));
      expect(url.queryParameters['page'], '1');

      adapter.respond();
      await future;
    });

    test('does not track skipped, excluded or paused calls', () async {
      setUpDio(
        const NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
          excludedUrls: ['/health'],
        ),
      );
      final skipped = dio.get<Object?>(
        '/skip',
        options: Options(extra: {Netoscope.skipLoggingKey: true}),
      );
      final excluded = dio.get<Object?>('/health');
      await pumpEventQueue();
      expect(netoscope.pendingCalls, isEmpty);

      netoscope.setLoggingEnabled(false);
      final paused = dio.get<Object?>('/paused');
      await pumpEventQueue();
      expect(netoscope.pendingCalls, isEmpty);

      adapter
        ..respond()
        ..respond()
        ..respond();
      await Future.wait([skipped, excluded, paused]);
    });

    test('keeps in-flight calls when the history is cleared', () async {
      setUpDio();
      final future = dio.get<Object?>('/slow');
      await pumpEventQueue();
      netoscope.clearLogs();
      expect(netoscope.pendingCalls, hasLength(1));

      adapter.respond();
      await future;
      expect(netoscope.logs, hasLength(1));
    });

    test('carries tags', () async {
      setUpDio();
      final future = netoscope.tagged(
        'checkout',
        () => dio.get<Object?>('/cart'),
      );
      await pumpEventQueue();
      expect(netoscope.pendingCalls.single.tags, ['checkout']);
      adapter.respond();
      await future;
    });
  });

  group('package:http', () {
    test('tracks a call until its body has been read', () async {
      netoscope = Netoscope(config: _quiet);
      final release = Completer<void>();
      final client = netoscope.httpClient(
        MockClient((request) async {
          await release.future;
          return http.Response('{"ok":true}', 200);
        }),
      );

      final future = client.get(Uri.parse('https://api.example.com/items'));
      await pumpEventQueue();
      final pending = netoscope.pendingCalls.single;
      expect(pending.url.path, '/items');

      release.complete();
      await future;
      expect(netoscope.pendingCalls, isEmpty);
      expect(netoscope.logs.single.id, pending.id);
    });

    test('ends tracking when the client throws', () async {
      netoscope = Netoscope(config: _quiet);
      final client = netoscope.httpClient(
        MockClient((_) async => throw http.ClientException('offline')),
      );

      await expectLater(
        client.get(Uri.parse('https://api.example.com/x')),
        throwsA(isA<http.ClientException>()),
      );
      expect(netoscope.pendingCalls, isEmpty);
    });
  });

  group('NetworkLogFilter.applyPending', () {
    final calls = [
      PendingNetworkCall(
        id: '1',
        method: 'GET',
        url: Uri.parse('https://api.dev/users'),
        startedAt: DateTime(2026),
        tags: const ['login'],
      ),
      PendingNetworkCall(
        id: '2',
        method: 'POST',
        url: Uri.parse('https://api.dev/orders'),
        startedAt: DateTime(2026),
      ),
    ];

    List<String> ids(NetworkLogFilter filter) =>
        [for (final c in filter.applyPending(calls)) c.id];

    test('shows every call without filters', () {
      expect(ids(const NetworkLogFilter()), ['1', '2']);
    });

    test('matches free text, method and tag', () {
      expect(ids(const NetworkLogFilter(query: 'orders')), ['2']);
      expect(ids(const NetworkLogFilter(query: 'GET users')), ['1']);
      expect(ids(const NetworkLogFilter(method: 'POST')), ['2']);
      expect(ids(const NetworkLogFilter(tag: 'login')), ['1']);
    });

    test('hides calls behind filters that need a response', () {
      expect(ids(const NetworkLogFilter(status: StatusFilter.success)), []);
      expect(ids(const NetworkLogFilter(onlySlow: true)), []);
      expect(ids(const NetworkLogFilter(query: 'status:2xx')), []);
      expect(
        ids(const NetworkLogFilter(protocols: {NetworkProtocol.webSocket})),
        [],
      );
    });
  });

  testWidgets('the inspector shows in-flight calls and then the result',
      (tester) async {
    netoscope = Netoscope(config: _quiet);
    final adapter = _GatedAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = adapter
      ..interceptors.add(netoscope.dioInterceptor);

    await tester.pumpWidget(
      MaterialApp(home: NetworkInspector(netoscope: netoscope)),
    );
    late Future<Object?> future;
    await tester.runAsync(() async {
      future = dio.get<Object?>('/reports');
      await pumpEventQueue();
    });
    await tester.pump();

    expect(find.text('/reports'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.textContaining('1 in flight'), findsOneWidget);

    await tester.runAsync(() async {
      adapter.respond();
      await future;
    });
    await tester.pump();

    expect(find.text('Pending'), findsNothing);
    expect(find.text('/reports'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
  });
}
