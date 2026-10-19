import 'network_logger_config.dart';

/// Runtime switches that can be changed while the app runs, from code or
/// from the inspector's settings panel.
///
/// They only take effect when logging is enabled by
/// `NetworkLoggerConfig.enabled` (which is off in release builds by
/// default); a disabled logger cannot be switched on at runtime.
class NetoscopeSettings {
  /// Creates settings.
  const NetoscopeSettings({
    this.recording = true,
    this.floatingButton = true,
    this.notification = true,
    this.themeMode = InspectorThemeMode.system,
  });

  /// Whether new network activity is recorded. Turning this off pauses
  /// capture; history is kept.
  final bool recording;

  /// Whether `NetworkInspectorButton` and `NetworkInspectorOverlay` show the
  /// floating button.
  final bool floatingButton;

  /// Whether the activity notification is shown (when a notifier is
  /// attached).
  final bool notification;

  /// The inspector's theme: follow the host app ([InspectorThemeMode.system])
  /// or force light or dark.
  final InspectorThemeMode themeMode;

  /// Returns a copy with the given values replaced.
  NetoscopeSettings copyWith({
    bool? recording,
    bool? floatingButton,
    bool? notification,
    InspectorThemeMode? themeMode,
  }) =>
      NetoscopeSettings(
        recording: recording ?? this.recording,
        floatingButton: floatingButton ?? this.floatingButton,
        notification: notification ?? this.notification,
        themeMode: themeMode ?? this.themeMode,
      );

  @override
  bool operator ==(Object other) =>
      other is NetoscopeSettings &&
      other.recording == recording &&
      other.floatingButton == floatingButton &&
      other.notification == notification &&
      other.themeMode == themeMode;

  @override
  int get hashCode =>
      Object.hash(recording, floatingButton, notification, themeMode);

  @override
  String toString() => 'NetoscopeSettings(recording: $recording, '
      'floatingButton: $floatingButton, notification: $notification, '
      'themeMode: ${themeMode.name})';
}
