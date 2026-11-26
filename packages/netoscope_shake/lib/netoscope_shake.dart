/// Shake-to-open support for Netoscope.
///
/// ```dart
/// MaterialApp(
///   navigatorKey: navigatorKey,
///   builder: (context, child) => NetoscopeShakeDetector(
///     netoscope: netoscope,
///     navigatorKey: navigatorKey,
///     child: child!,
///   ),
/// )
/// ```
library;

export 'src/netoscope_shake_detector.dart' show NetoscopeShakeDetector;
export 'src/shake_detector.dart' show ShakeDetector, standardGravity;
