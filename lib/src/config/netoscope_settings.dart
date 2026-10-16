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

  /// Returns a copy with the given values replaced.
  NetoscopeSettings copyWith({
    bool? recording,
    bool? floatingButton,
    bool? notification,
  }) =>
      NetoscopeSettings(
        recording: recording ?? this.recording,
        floatingButton: floatingButton ?? this.floatingButton,
        notification: notification ?? this.notification,
      );

  @override
  bool operator ==(Object other) =>
      other is NetoscopeSettings &&
      other.recording == recording &&
      other.floatingButton == floatingButton &&
      other.notification == notification;

  @override
  int get hashCode => Object.hash(recording, floatingButton, notification);

  @override
  String toString() => 'NetoscopeSettings(recording: $recording, '
      'floatingButton: $floatingButton, notification: $notification)';
}
