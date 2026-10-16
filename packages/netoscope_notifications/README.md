# netoscope_notifications

Local-notification support for [Netoscope](../../README.md).

This package shows recent network activity in a quiet notification. Tapping
it opens the Netoscope inspector, whether the app is in the foreground, in
the background, or was launched from the notification.

It lives in its own package because it depends on
`flutter_local_notifications`, which needs native setup. Apps that only use
Netoscope's console or in-app inspector don't need it.

## Usage

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final netoscope = Netoscope();

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    NetoscopeNotifications.attach(netoscope, navigatorKey: navigatorKey);
  }

  @override
  Widget build(BuildContext context) =>
      MaterialApp(navigatorKey: navigatorKey, home: const HomePage());
}
```

`attach` initializes the plugin, asks for notification permission (pass
`requestPermission: false` to skip that) and attaches the notifier. It
returns `null` and does nothing when Netoscope is disabled for the build
(the release default), on the web, or where the plugin isn't available.

Switch the notification at runtime with
`netoscope.setNotificationEnabled(bool)`, or from the inspector's settings
panel.

For full control, create a `LocalNotificationNotifier` yourself, call
`initialize()`, set `onTap`, and pass it to `netoscope.attachNotifier(…)`.

## What it looks like

```
◎ your_app · 1 failed · now
Netoscope · 3 requests
✕ GET 404  /orders/42 · 99 ms
✓ POST 200  /auth/login · 254 ms
✓ GET 200  /users · 216 ms
OPEN    PAUSE    CLEAR
```

- **Android:**
  - An ongoing, silent notification in the "Network inspector" channel (low
    importance), updated in place.
  - **Collapsed:** the latest call. **Expanded:** up to five calls, with bold
    methods.
  - **Header:** "All OK", "N failed" and/or "Paused".
  - Your accent color and status-bar icon.
  - **Lock screen:** the content is hidden (`NotificationVisibility.private`),
    because URLs can be sensitive.
- **iOS/macOS:**
  - A passive entry in Notification Center, with the status as subtitle and
    up to three calls.
  - No banner or sound, unless `showBanner: true`.
  - Long-press to reveal the actions.
- **Actions:**
  - **Open** opens the inspector.
  - **Pause/Resume** switches recording; the label follows the current state.
  - **Clear** clears the history, which also removes the notification.
  - Actions bring the app to the foreground. Turn them off with
    `showActions: false`.

### Android status-bar icon

Android draws the small icon as a white silhouette, so a full-color launcher
icon shows up as a plain square. Add a white-on-transparent vector drawable,
such as `android/app/src/main/res/drawable/ic_stat_netoscope.xml`, and pass
its name:

```dart
NetoscopeNotifications.attach(
  netoscope,
  navigatorKey: navigatorKey,
  androidIcon: 'ic_stat_netoscope',
  accentColor: const Color(0xFF4F6BED),
);
```

The icon is referenced only from Dart, so stop release builds from shrinking
it away by adding `res/raw/keep.xml`:

```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_netoscope" />
```

The example app includes both files.

## Platform setup

### Android

`flutter_local_notifications` requires core-library desugaring. In
`android/app/build.gradle.kts`:

```kotlin
android {
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

The plugin declares the `POST_NOTIFICATIONS` permission. `attach` asks for
it at runtime on Android 13 and later.

### iOS

In `ios/Runner/AppDelegate.swift`, inside
`application(_:didFinishLaunchingWithOptions:)`:

```swift
UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
```

## Requirements

- Dart `^3.8.0` and Flutter `>=3.32.0` (required by
  `flutter_local_notifications` 20).
- `netoscope`. Until it is published, this package uses a path dependency
  and is marked `publish_to: none`.

## License

MIT
