// A loopback server for the native and dart:io demos (not on the web).
export 'local_server_stub.dart' if (dart.library.io) 'local_server_io.dart';
