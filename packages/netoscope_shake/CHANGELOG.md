## 0.1.0

- `NetoscopeShakeDetector`: opens the Netoscope inspector when the device is
  shaken. Listens to the accelerometer (`sensors_plus`) only while mounted
  and while the inspector is available, never opens a second inspector, and
  does nothing on platforms without an accelerometer.
- Configurable `threshold` (g), `minJolts`, `window` and `cooldown`, an
  `enabled` switch, an `onShake` callback and an injectable
  `accelerometerEvents` stream.
- `ShakeDetector`: the platform-independent shake recognizer used by the
  widget.
