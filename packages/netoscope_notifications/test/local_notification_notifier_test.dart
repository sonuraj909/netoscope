import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope_notifications/netoscope_notifications.dart';

class _FakePlugin extends Fake implements FlutterLocalNotificationsPlugin {
  DidReceiveNotificationResponseCallback? onResponse;
  NotificationAppLaunchDetails? launchDetails;
  final List<
    ({
      int id,
      String? title,
      String? body,
      NotificationDetails? details,
      String? payload,
    })
  >
  shown = [];
  final List<int> cancelled = [];

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    onResponse = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launchDetails;

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async => shown.add((
    id: id,
    title: title,
    body: body,
    details: notificationDetails,
    payload: payload,
  ));

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelled.add(id);

  void tap(String? payload, {String? action}) => onResponse!(
    NotificationResponse(
      notificationResponseType: action == null
          ? NotificationResponseType.selectedNotification
          : NotificationResponseType.selectedNotificationAction,
      actionId: action,
      payload: payload,
    ),
  );
}

NetworkLogEntry _entry(String path, {int status = 200, Duration? duration}) =>
    NetworkLogEntry(
      id: path,
      method: 'GET',
      url: Uri.parse('https://api.dev').replace(path: path),
      timestamp: DateTime(2026),
      statusCode: status,
      duration: duration,
    );

void main() {
  late _FakePlugin plugin;

  setUp(() => plugin = _FakePlugin());

  test('does nothing before initialize', () async {
    final notifier = LocalNotificationNotifier(plugin: plugin);
    await notifier.show(
      NetworkActivitySummary(total: 1, failures: 0, recent: []),
    );
    await notifier.hide();
    expect(plugin.shown, isEmpty);
    expect(plugin.cancelled, isEmpty);
  });

  group('formatting', () {
    test('lines show a mark, method, status, path and duration', () {
      final ok = _entry('/users', duration: const Duration(milliseconds: 87));
      expect(formatActivityLine(ok), '✓ GET 200  /users · 87 ms');
      expect(
        formatActivityLine(_entry('/pay', status: 500)),
        '✕ GET 500  /pay',
      );
    });

    test('HTML lines bold the method and escape the rest', () {
      expect(
        formatActivityLine(_entry('/a&b'), html: true),
        '✓ <b>GET</b> 200&nbsp;&nbsp;/a&amp;b',
      );
    });

    test('the header reports failures and pauses', () {
      expect(
        LocalNotificationNotifier.statusText(
          NetworkActivitySummary(total: 3, failures: 0, recent: const []),
        ),
        'All OK',
      );
      expect(
        LocalNotificationNotifier.statusText(
          NetworkActivitySummary(
            total: 3,
            failures: 2,
            recent: const [],
            isRecording: false,
          ),
        ),
        '2 failed · Paused',
      );
    });
  });

  test('shows a quiet, ongoing, private summary with actions', () async {
    final notifier = LocalNotificationNotifier(plugin: plugin);
    expect(await notifier.initialize(), isTrue);

    await notifier.show(
      NetworkActivitySummary(
        total: 12,
        failures: 1,
        recent: [_entry('/pay', status: 500), _entry('/users')],
      ),
    );

    final shown = plugin.shown.single;
    expect(shown.id, notifier.notificationId);
    expect(shown.title, 'Netoscope · 12 requests');
    // Android: one collapsed line; the expanded inbox lists every call.
    expect(shown.body, '✕ GET 500  /pay');
    expect(shown.payload, LocalNotificationNotifier.payload);

    final android = shown.details!.android!;
    expect(android.ongoing, isTrue);
    expect(android.silent, isTrue);
    expect(android.onlyAlertOnce, isTrue);
    expect(android.importance, Importance.low);
    expect(android.visibility, NotificationVisibility.private);
    expect(android.subText, '1 failed');
    expect(android.color, notifier.accentColor);
    expect(android.when, DateTime(2026).millisecondsSinceEpoch);
    expect(android.actions!.map((a) => a.title), ['Open', 'Pause', 'Clear']);
    expect(android.actions!.every((a) => !a.cancelNotification), isTrue);
    final inbox = android.styleInformation! as InboxStyleInformation;
    expect(inbox.htmlFormatLines, isTrue);
    expect(inbox.lines.first, '✕ <b>GET</b> 500&nbsp;&nbsp;/pay');
    expect(inbox.summaryText, 'Tap to open the inspector');

    final ios = shown.details!.iOS!;
    expect(ios.presentBanner, isFalse);
    expect(ios.presentList, isTrue);
    expect(ios.presentSound, isFalse);
    expect(ios.subtitle, '1 failed');
    expect(ios.categoryIdentifier, 'netoscope.recording');
    expect(ios.interruptionLevel, InterruptionLevel.passive);

    await notifier.hide();
    expect(plugin.cancelled, [notifier.notificationId]);
  });

  test('iOS bodies list up to three calls', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final notifier = LocalNotificationNotifier(plugin: plugin);
    await notifier.initialize();

    await notifier.show(
      NetworkActivitySummary(
        total: 4,
        failures: 1,
        recent: [
          _entry('/pay', status: 500),
          _entry('/users'),
          _entry('/a'),
          _entry('/b'),
        ],
      ),
    );

    expect(
      plugin.shown.single.body,
      '✕ GET 500  /pay\n✓ GET 200  /users\n✓ GET 200  /a',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  test('a paused summary offers Resume', () async {
    final notifier = LocalNotificationNotifier(plugin: plugin);
    await notifier.initialize();
    await notifier.show(
      NetworkActivitySummary(
        total: 1,
        failures: 0,
        recent: [_entry('/users')],
        isRecording: false,
      ),
    );

    final details = plugin.shown.single.details!;
    expect(details.android!.actions![1].title, 'Resume');
    expect(details.android!.subText, 'All OK · Paused');
    expect(
      (details.android!.styleInformation! as InboxStyleInformation).summaryText,
      'Recording paused',
    );
    expect(details.iOS!.categoryIdentifier, 'netoscope.paused');
  });

  test('actions can be turned off', () async {
    final notifier = LocalNotificationNotifier(
      plugin: plugin,
      showActions: false,
    );
    await notifier.initialize();
    await notifier.show(
      NetworkActivitySummary(total: 1, failures: 0, recent: [_entry('/a')]),
    );
    expect(plugin.shown.single.details!.android!.actions, isNull);
    expect(plugin.shown.single.details!.iOS!.categoryIdentifier, isNull);
  });

  test('actions call their callbacks', () async {
    final calls = <String>[];
    final notifier = LocalNotificationNotifier(
      plugin: plugin,
      onTap: () => calls.add('open'),
      onToggleRecording: () => calls.add('toggle'),
      onClear: () => calls.add('clear'),
    );
    await notifier.initialize();

    plugin
      ..tap(
        LocalNotificationNotifier.payload,
        action: NetoscopeNotificationActions.open,
      )
      ..tap(
        LocalNotificationNotifier.payload,
        action: NetoscopeNotificationActions.toggleRecording,
      )
      ..tap(
        LocalNotificationNotifier.payload,
        action: NetoscopeNotificationActions.clear,
      )
      ..tap(LocalNotificationNotifier.payload);
    expect(calls, ['open', 'toggle', 'clear', 'open']);
  });

  test('only its own notification triggers onTap', () async {
    var taps = 0;
    final notifier = LocalNotificationNotifier(
      plugin: plugin,
      onTap: () => taps++,
    );
    await notifier.initialize();

    plugin.tap('something-else');
    expect(taps, 0);
    plugin.tap(LocalNotificationNotifier.payload);
    expect(taps, 1);
  });

  testWidgets('a launch from the notification opens after the first frame', (
    tester,
  ) async {
    var taps = 0;
    plugin.launchDetails = const NotificationAppLaunchDetails(
      true,
      notificationResponse: NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: LocalNotificationNotifier.payload,
      ),
    );
    final notifier = LocalNotificationNotifier(
      plugin: plugin,
      onTap: () => taps++,
    );

    await notifier.initialize();
    expect(taps, 0);
    await tester.pumpWidget(const SizedBox());
    expect(taps, 1);
  });

  group('NetoscopeNotifications.attach', () {
    testWidgets('wires the notifier and opens the inspector on tap', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final netoscope = Netoscope(
        config: const NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
        ),
        notificationInterval: Duration.zero,
      );
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
      );

      final notifier = await NetoscopeNotifications.attach(
        netoscope,
        navigatorKey: navigatorKey,
        plugin: plugin,
      );
      expect(notifier, isNotNull);
      expect(netoscope.hasNotifier, isTrue);

      plugin.tap(LocalNotificationNotifier.payload);
      await tester.pumpAndSettle();
      expect(find.byType(NetworkInspector), findsOneWidget);

      // A second tap does not stack another inspector.
      plugin.tap(LocalNotificationNotifier.payload);
      await tester.pumpAndSettle();
      expect(find.byType(NetworkInspector), findsOneWidget);

      // Pause/Resume and Clear act on the logger.
      plugin.tap(
        LocalNotificationNotifier.payload,
        action: NetoscopeNotificationActions.toggleRecording,
      );
      expect(netoscope.isRecording, isFalse);
      plugin.tap(
        LocalNotificationNotifier.payload,
        action: NetoscopeNotificationActions.toggleRecording,
      );
      expect(netoscope.isRecording, isTrue);
      plugin.tap(
        LocalNotificationNotifier.payload,
        action: NetoscopeNotificationActions.clear,
      );
      expect(netoscope.logs, isEmpty);
    });

    test('is a no-op when logging is disabled for the build', () async {
      final netoscope = Netoscope(
        config: const NetworkLoggerConfig(enabled: false),
      );
      final notifier = await NetoscopeNotifications.attach(
        netoscope,
        navigatorKey: GlobalKey<NavigatorState>(),
        plugin: plugin,
      );
      expect(notifier, isNull);
      expect(plugin.onResponse, isNull);
    });
  });
}
