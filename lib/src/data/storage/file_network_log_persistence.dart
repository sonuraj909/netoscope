// A file-backed persistence where dart:io exists; unsupported on the web.
export 'file_network_log_persistence_stub.dart'
    if (dart.library.io) 'file_network_log_persistence_io.dart';
