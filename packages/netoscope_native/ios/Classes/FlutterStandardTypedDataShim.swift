import Flutter

/// Wraps bytes so they arrive in Dart as a `Uint8List`.
enum FlutterStandardTypedDataShim {
  static func wrap(_ data: Data) -> FlutterStandardTypedData {
    FlutterStandardTypedData(bytes: data)
  }
}
