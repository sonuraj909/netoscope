/// Local-notification support for Netoscope.
///
/// ```dart
/// final netoscope = Netoscope();
/// await NetoscopeNotifications.attach(netoscope, navigatorKey: navigatorKey);
/// ```
library;

export 'src/local_notification_notifier.dart'
    show
        LocalNotificationNotifier,
        NetoscopeNotificationActions,
        NetoscopeNotifications,
        formatActivityLine;
