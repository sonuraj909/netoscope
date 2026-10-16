import '../log_capture.dart';

/// Installed `dart:io` capture. Not available on this platform.
abstract interface class DartIoCapture {
  /// Restores the previous `HttpOverrides`.
  void uninstall();
}

/// Returns `null`: `dart:io` is not available on this platform.
DartIoCapture? installDartIoCapture(LogCapture capture) => null;
