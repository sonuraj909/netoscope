import '../entities/network_log_entry.dart';

/// A destination that receives each completed [NetworkLogEntry], such as the
/// console or a custom reporter.
///
/// Entries reaching a sink have already been redacted. Implementations must
/// not throw; failures are caught and ignored so they never affect requests.
abstract interface class NetworkLogSink {
  /// Handles a newly recorded [entry].
  void write(NetworkLogEntry entry);
}
