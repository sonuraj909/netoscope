# netoscope_shake

Shake-to-open support for [Netoscope](../../README.md).

Shake the device to open the Netoscope inspector from any screen, without
keeping a floating button on screen.

It lives in its own package because it depends on `sensors_plus`, a plugin
with native code. Apps that only use Netoscope's console, floating button or
notification don't need it.

## Usage

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final netoscope = Netoscope();

MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => NetoscopeShakeDetector(
    netoscope: netoscope,
    navigatorKey: navigatorKey,
    child: child!,
  ),
  home: const HomePage(),
);
```

`MaterialApp.builder` places the detector above the app's `Navigator`, so
pass the `navigatorKey`. Below the `Navigator` (for example wrapping a single
screen) the key is optional.

The detector:

- listens to the accelerometer only while it is mounted, and only when
  `netoscope.isInspectorAvailable` is `true`. It is inert in release builds,
  where Netoscope is disabled by default, so it can stay in the tree;
- never opens a second inspector while one is shown;
- does nothing on platforms without an accelerometer (desktop, most
  simulators). To try it on the iOS Simulator use **Device ▸ Shake**; on the
  Android emulator use the virtual sensors panel.

It combines with `NetworkInspectorOverlay`: wrap one in the other.

## Tuning

| Parameter | Default | Meaning |
| --- | --- | --- |
| `threshold` | `2.7` | Total acceleration, in g (gravity included), that counts as a jolt |
| `minJolts` | `2` | Jolts needed within `window` |
| `window` | 600 ms | Time span for `minJolts` jolts |
| `cooldown` | 1500 ms | Shakes ignored after one is detected |
| `samplingPeriod` | `SensorInterval.uiInterval` | Accelerometer sampling rate |
| `enabled` | `true` | Set to `false` to stop listening without removing the widget |

`onShake` is called on every detected shake, before the inspector opens.
`accelerometerEvents` replaces the sensor stream, for example in widget
tests. `ShakeDetector` is the platform-independent recognizer the widget
uses, if you want to drive your own action from shakes.
