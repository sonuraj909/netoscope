import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netoscope/netoscope.dart';

import 'support/fixtures.dart';

class _FakeNotifier implements NetworkActivityNotifier {
  final List<NetworkActivitySummary> shown = [];
  int hidden = 0;

  @override
  Future<void> show(NetworkActivitySummary summary) async => shown.add(summary);

  @override
  Future<void> hide() async => hidden++;
}

class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString('ok', 200);

  @override
  void close({bool force = false}) {}
}

const _quiet = NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none);

void main() {
  group('recording switch', () {
    test('pausing stops capture everywhere; history is kept', () async {
      final netoscope = Netoscope(config: _quiet);
      final dio = Dio()
        ..httpClientAdapter = _OkAdapter()
        ..interceptors.add(netoscope.dioInterceptor);
      final client = netoscope.httpClient(
        MockClient((_) async => http.Response('ok', 200)),
      );
      final socket = netoscope.webSocket(Uri.parse('wss://rt.dev'));

      await dio.get<void>('https://a.dev/before');
      expect(netoscope.logs, hasLength(1));

      netoscope.setLoggingEnabled(false);
      expect(netoscope.isRecording, isFalse);
      await dio.get<void>('https://a.dev/paused');
      await client.get(Uri.parse('https://a.dev/paused'));
      socket.received('paused');
      expect(netoscope.logs.map((e) => e.url.path), ['/before']);

      netoscope.setLoggingEnabled(true);
      await client.get(Uri.parse('https://a.dev/after'));
      socket.received('after');
      expect(netoscope.logs, hasLength(3));
      await netoscope.dispose();
    });

    test('settings changes are broadcast', () async {
      final netoscope = Netoscope(config: _quiet);
      final seen = <NetoscopeSettings>[];
      final sub = netoscope.settingsChanges.listen(seen.add);

      netoscope
        ..setFloatingButtonEnabled(false)
        ..setFloatingButtonEnabled(false) // no change, no event
        ..setNotificationEnabled(false);
      await pumpEventQueue();

      expect(seen, [
        const NetoscopeSettings(floatingButton: false),
        const NetoscopeSettings(floatingButton: false, notification: false),
      ]);
      expect(netoscope.isFloatingButtonVisible, isFalse);
      await sub.cancel();
      await netoscope.dispose();
    });

    test('config sets the initial switches', () {
      final netoscope = Netoscope(
        config: const NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
          showFloatingButton: false,
          showNotification: false,
        ),
      );
      expect(
        netoscope.settings,
        const NetoscopeSettings(floatingButton: false, notification: false),
      );
    });

    test('a logger disabled for the build cannot be switched on', () {
      final notifier = _FakeNotifier();
      final netoscope = Netoscope(
        config: const NetworkLoggerConfig(enabled: false),
        notifier: notifier,
      )..setLoggingEnabled(true);

      expect(netoscope.isRecording, isFalse);
      expect(netoscope.hasNotifier, isFalse);
      expect(netoscope.isFloatingButtonVisible, isFalse);
    });
  });

  group('activity notification', () {
    late _FakeNotifier notifier;
    late InMemoryNetworkLogStore store;
    late Netoscope netoscope;

    setUp(() {
      notifier = _FakeNotifier();
      store = InMemoryNetworkLogStore();
      netoscope = Netoscope(
        config: _quiet,
        store: store,
        notifier: notifier,
        notificationInterval: const Duration(milliseconds: 20),
      );
    });

    test('shows a throttled summary of recent activity', () async {
      expect(netoscope.isNotificationActive, isTrue);
      expect(notifier.hidden, 1, reason: 'empty history hides it');

      for (var i = 0; i < 7; i++) {
        store.add(makeEntry(id: '$i', url: 'https://a.dev/item/$i'));
      }
      store.add(makeEntry(
          id: 'x', method: 'POST', statusCode: 500, url: 'https://a.dev/pay'));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(notifier.shown, hasLength(1), reason: 'bursts are coalesced');
      final summary = notifier.shown.single;
      expect(summary.total, 8);
      expect(summary.failures, 1);
      expect(summary.recent, hasLength(5));
      expect(summary.title, 'Netoscope · 8 requests');
      expect(summary.lines.first, 'POST 500 /pay');
      expect(summary.body, 'POST 500 /pay · 1 failed');
    });

    test('switching off hides it; switching on shows it again', () async {
      store.add(makeEntry());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final hiddenBefore = notifier.hidden;

      netoscope.setNotificationEnabled(false);
      expect(notifier.hidden, hiddenBefore + 1);
      store.add(makeEntry(id: 'quiet'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final shownWhileOff = notifier.shown.length;

      netoscope.setNotificationEnabled(true);
      expect(notifier.shown.length, shownWhileOff + 1);
      expect(notifier.shown.last.total, 2);
    });

    test('clearing the history hides it', () async {
      store.add(makeEntry());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final hiddenBefore = notifier.hidden;

      netoscope.clearLogs();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(notifier.hidden, hiddenBefore + 1);
    });

    test('notifiers can be attached and detached later', () async {
      final later = Netoscope(config: _quiet);
      expect(later.hasNotifier, isFalse);

      final attached = _FakeNotifier();
      later.attachNotifier(attached);
      expect(later.hasNotifier, isTrue);

      later.attachNotifier(null);
      expect(later.hasNotifier, isFalse);
      expect(attached.hidden, 2, reason: 'hidden on attach (empty) and detach');
    });

    test('dispose removes the notification', () async {
      final before = notifier.hidden;
      await netoscope.dispose();
      expect(notifier.hidden, before + 1);
    });
  });

  group('UI', () {
    Future<void> pumpApp(WidgetTester tester, Netoscope netoscope) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => NetworkInspectorOverlay(
            netoscope: netoscope,
            navigatorKey: navigatorKey,
            child: child!,
          ),
          home: const Scaffold(body: Text('home')),
        ),
      );
    }

    testWidgets('the floating button follows its switch', (tester) async {
      final netoscope = Netoscope(config: _quiet);
      await pumpApp(tester, netoscope);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      netoscope.setFloatingButtonEnabled(false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsNothing);

      netoscope.setFloatingButtonEnabled(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('the settings sheet switches recording and the button',
        (tester) async {
      final netoscope = Netoscope(config: _quiet);
      await tester.pumpWidget(
        MaterialApp(home: NetworkInspector(netoscope: netoscope)),
      );

      await tester.tap(find.byTooltip('Inspector settings'));
      await tester.pumpAndSettle();
      expect(
        find.text('Attach a notifier (netoscope_notifications) to enable.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Record network activity'));
      await tester.pumpAndSettle();
      expect(netoscope.isRecording, isFalse);
      expect(find.text('Paused: new calls are not captured.'), findsOneWidget);

      await tester.tap(find.text('Floating button'));
      await tester.pumpAndSettle();
      expect(netoscope.settings.floatingButton, isFalse);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Recording paused'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(netoscope.isRecording, isTrue);
      expect(find.text('Recording paused'), findsNothing);
    });

    testWidgets('the notification switch works when a notifier is attached',
        (tester) async {
      final notifier = _FakeNotifier();
      final netoscope = Netoscope(config: _quiet, notifier: notifier);
      await tester.pumpWidget(
        MaterialApp(home: NetworkInspector(netoscope: netoscope)),
      );

      await tester.tap(find.byTooltip('Inspector settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notification'));
      await tester.pumpAndSettle();

      expect(netoscope.isNotificationActive, isFalse);
      expect(netoscope.settings.notification, isFalse);
    });
  });
}
