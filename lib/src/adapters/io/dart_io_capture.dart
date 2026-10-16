// dart:io HttpClient capture where dart:io exists; a no-op elsewhere (web).
export 'dart_io_capture_stub.dart'
    if (dart.library.io) 'dart_io_capture_io.dart';
