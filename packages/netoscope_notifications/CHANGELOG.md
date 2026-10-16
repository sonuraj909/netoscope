## 0.1.0

- Notification design:
  - A `✓/✕` line per call with the method, status, path and duration
    (`formatActivityLine`).
  - A status header ("All OK", "N failed", "Paused") and a timestamp.
  - An accent color and a configurable status-bar icon.
  - Content hidden on the Android lock screen.
- Open, Pause/Resume and Clear actions on Android and iOS
  (`NetoscopeNotificationActions`); the Pause label follows the recording
  state.

- `LocalNotificationNotifier`: a quiet, ongoing activity notification built
  on `flutter_local_notifications` 20. Tapping it calls `onTap`, including
  when the tap launches the app.
- `NetoscopeNotifications.attach`: one-call setup that opens the inspector
  on tap and is a no-op when Netoscope is disabled or notifications are
  unavailable.
