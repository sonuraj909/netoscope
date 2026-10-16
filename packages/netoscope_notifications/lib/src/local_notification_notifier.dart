import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:netoscope/netoscope.dart';

/// Action identifiers used by Netoscope's notification.
abstract final class NetoscopeNotificationActions {
  /// Opens the inspector.
  static const String open = 'netoscope.open';

  /// Pauses or resumes recording.
  static const String toggleRecording = 'netoscope.toggle-recording';

  /// Clears the history.
  static const String clear = 'netoscope.clear';
}

const String _recordingCategory = 'netoscope.recording';
const String _pausedCategory = 'netoscope.paused';

/// One line describing an event, such as `✓ POST 200  /auth/login · 243 ms`.
///
/// With [html], the method is bold and the text is escaped for Android's
/// `InboxStyle`.
String formatActivityLine(NetworkLogEntry entry, {bool html = false}) {
  final failed = !entry.isSuccess || entry.hasGraphQLErrors;
  final status =
      entry.statusCode?.toString() ??
      (entry.isSuccess ? 'OK' : entry.outcome.name.toUpperCase());
  final path = entry.url.path.isEmpty ? '/' : entry.url.path;
  final duration = entry.duration == null || entry.duration == Duration.zero
      ? ''
      : ' · ${entry.duration!.inMilliseconds} ms';
  final mark = failed ? '✕' : '✓';
  if (!html) return '$mark ${entry.method} $status  $path$duration';
  return '$mark <b>${_escape(entry.method)}</b> ${_escape(status)}'
      '&nbsp;&nbsp;${_escape(path)}${_escape(duration)}';
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// A [NetworkActivityNotifier] backed by `flutter_local_notifications`.
///
/// Shows one quiet notification that is updated in place:
/// - **Android:** an ongoing, silent notification with an accent color, a
///   `✓/✕` line per recent call (method, status, path, duration), a failure
///   summary in the header and **Open**, **Pause/Resume** and **Clear**
///   actions. Content is hidden on the lock screen.
/// - **iOS/macOS:** a passive Notification Center entry with a subtitle, the
///   latest calls and the same actions (long-press to reveal). No banner or
///   sound unless [showBanner] is set.
///
/// Tapping the notification calls [onTap]; the actions call [onTap],
/// [onToggleRecording] and [onClear].
class LocalNotificationNotifier implements NetworkActivityNotifier {
  /// Creates a notifier. Call [initialize] before use.
  LocalNotificationNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    this.onTap,
    this.onToggleRecording,
    this.onClear,
    this.notificationId = 0x4E54,
    this.androidChannelId = 'netoscope_activity',
    this.androidChannelName = 'Network inspector',
    this.androidIcon = '@mipmap/ic_launcher',
    this.accentColor = const Color(0xFF4F6BED),
    this.showActions = true,
    this.showBanner = false,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// The payload that identifies Netoscope's notification.
  static const String payload = 'netoscope.open-inspector';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Called when the notification (or its Open action) is tapped.
  VoidCallback? onTap;

  /// Called by the Pause/Resume action.
  VoidCallback? onToggleRecording;

  /// Called by the Clear action.
  VoidCallback? onClear;

  /// The notification ID. Change it if it clashes with your app's.
  final int notificationId;

  /// The Android channel ID.
  final String androidChannelId;

  /// The Android channel name shown in system settings.
  final String androidChannelName;

  /// The Android small icon resource. Use a white-on-transparent drawable
  /// (for example `ic_stat_netoscope`); full-color launcher icons render as
  /// a plain square on Android 5 and later.
  final String androidIcon;

  /// The Android accent color (icon tint and app name).
  final Color accentColor;

  /// Whether Open, Pause/Resume and Clear actions are shown.
  final bool showActions;

  /// Whether iOS/macOS show a banner when the notification updates. Off by
  /// default so frequent updates stay unobtrusive.
  final bool showBanner;

  /// Whether [initialize] has completed.
  bool get isInitialized => _initialized;

  /// Initializes the plugin and, when [requestPermission] is set, asks for
  /// notification permission. Returns whether notifications are allowed.
  ///
  /// If the app was launched from the notification, the matching callback
  /// runs after the first frame.
  Future<bool> initialize({bool requestPermission = true}) async {
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: showActions ? _darwinCategories : const [],
    );
    await _plugin.initialize(
      settings: InitializationSettings(
        android: AndroidInitializationSettings(androidIcon),
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    _initialized = true;
    final allowed = requestPermission ? await _requestPermission() : true;

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onResponse(response),
      );
    }
    return allowed;
  }

  static final List<DarwinNotificationCategory> _darwinCategories = [
    for (final (id, toggleTitle) in [
      (_recordingCategory, 'Pause recording'),
      (_pausedCategory, 'Resume recording'),
    ])
      DarwinNotificationCategory(
        id,
        actions: [
          DarwinNotificationAction.plain(
            NetoscopeNotificationActions.open,
            'Open inspector',
            options: {DarwinNotificationActionOption.foreground},
          ),
          DarwinNotificationAction.plain(
            NetoscopeNotificationActions.toggleRecording,
            toggleTitle,
            options: {DarwinNotificationActionOption.foreground},
          ),
          DarwinNotificationAction.plain(
            NetoscopeNotificationActions.clear,
            'Clear history',
            options: {
              DarwinNotificationActionOption.foreground,
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
      ),
  ];

  void _onResponse(NotificationResponse response) {
    if (response.payload != payload) return;
    switch (response.actionId) {
      case NetoscopeNotificationActions.toggleRecording:
        onToggleRecording?.call();
      case NetoscopeNotificationActions.clear:
        onClear?.call();
      default:
        onTap?.call();
    }
  }

  Future<bool> _requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true) ?? false;
    }
    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (macos != null) {
      return await macos.requestPermissions(alert: true) ?? false;
    }
    return true;
  }

  /// The header text: failures, pause state or an all-clear.
  static String statusText(NetworkActivitySummary summary) {
    final parts = [
      if (summary.failures > 0) '${summary.failures} failed' else 'All OK',
      if (!summary.isRecording) 'Paused',
    ];
    return parts.join(' · ');
  }

  @override
  Future<void> show(NetworkActivitySummary summary) async {
    if (!_initialized) return;
    final latest = summary.latest;
    final status = statusText(summary);
    final title = summary.title;
    final latestLine = latest == null
        ? 'No requests yet'
        : formatActivityLine(latest);
    final darwin = DarwinNotificationDetails(
      presentAlert: showBanner,
      presentBanner: showBanner,
      presentList: true,
      presentSound: false,
      presentBadge: false,
      subtitle: status,
      threadIdentifier: 'netoscope',
      categoryIdentifier: showActions
          ? (summary.isRecording ? _recordingCategory : _pausedCategory)
          : null,
      interruptionLevel: InterruptionLevel.passive,
    );
    try {
      await _plugin.show(
        id: notificationId,
        title: title,
        // Android shows the body as one collapsed line (the expanded inbox
        // lists every call); iOS/macOS show up to three lines.
        body: defaultTargetPlatform == TargetPlatform.android
            ? latestLine
            : [
                for (final entry in summary.recent.take(3))
                  formatActivityLine(entry),
              ].join('\n'),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            androidChannelId,
            androidChannelName,
            channelDescription:
                'Recent network activity recorded by Netoscope.',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
            color: accentColor,
            subText: status,
            ticker: latestLine,
            showWhen: latest != null,
            when: latest?.timestamp.millisecondsSinceEpoch,
            category: AndroidNotificationCategory.status,
            visibility: NotificationVisibility.private,
            styleInformation: InboxStyleInformation(
              [
                for (final entry in summary.recent)
                  formatActivityLine(entry, html: true),
              ],
              htmlFormatLines: true,
              contentTitle: '<b>${_escape(title)}</b>',
              htmlFormatContentTitle: true,
              summaryText: summary.isRecording
                  ? 'Tap to open the inspector'
                  : 'Recording paused',
            ),
            actions: showActions
                ? [
                    const AndroidNotificationAction(
                      NetoscopeNotificationActions.open,
                      'Open',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                    AndroidNotificationAction(
                      NetoscopeNotificationActions.toggleRecording,
                      summary.isRecording ? 'Pause' : 'Resume',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                    const AndroidNotificationAction(
                      NetoscopeNotificationActions.clear,
                      'Clear',
                      showsUserInterface: true,
                      cancelNotification: false,
                    ),
                  ]
                : null,
          ),
          iOS: darwin,
          macOS: darwin,
        ),
        payload: payload,
      );
    } catch (_) {
      // Notifications are best-effort and must never affect the app.
    }
  }

  @override
  Future<void> hide() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: notificationId);
    } catch (_) {
      // Best-effort.
    }
  }
}

/// One-call setup for the Netoscope activity notification.
abstract final class NetoscopeNotifications {
  /// Creates and initializes a [LocalNotificationNotifier] wired to
  /// [netoscope], and attaches it:
  /// - tapping the notification (or **Open**) opens the inspector on
  ///   [navigatorKey];
  /// - **Pause/Resume** switches recording;
  /// - **Clear** clears the history (which also removes the notification).
  ///
  /// Returns `null` without attaching anything when logging is disabled for
  /// this build, on the web, or when the notification plugin is unavailable
  /// (for example in widget tests), so it is safe to call unconditionally.
  static Future<LocalNotificationNotifier?> attach(
    Netoscope netoscope, {
    required GlobalKey<NavigatorState> navigatorKey,
    bool requestPermission = true,
    bool showBanner = false,
    bool showActions = true,
    String androidIcon = '@mipmap/ic_launcher',
    Color accentColor = const Color(0xFF4F6BED),
    FlutterLocalNotificationsPlugin? plugin,
  }) async {
    if (!netoscope.isEnabled || (kIsWeb && plugin == null)) return null;
    final notifier = LocalNotificationNotifier(
      plugin: plugin,
      showBanner: showBanner,
      showActions: showActions,
      androidIcon: androidIcon,
      accentColor: accentColor,
      onTap: () {
        final navigator = navigatorKey.currentState;
        if (navigator != null) unawaited(netoscope.openInspectorOn(navigator));
      },
      onToggleRecording: () =>
          netoscope.setLoggingEnabled(!netoscope.isRecording),
      onClear: netoscope.clearLogs,
    );
    try {
      await notifier.initialize(requestPermission: requestPermission);
    } catch (_) {
      return null;
    }
    netoscope.attachNotifier(notifier);
    return notifier;
  }
}
