import '../contracts/network_log_store.dart';
import '../entities/network_log_entry.dart';

/// Reads and observes the recorded history.
class GetNetworkLogs {
  /// Creates the use case.
  const GetNetworkLogs(this._store);

  final NetworkLogStore _store;

  /// The current history, newest first.
  List<NetworkLogEntry> call() => _store.entries;

  /// Emits the full history, newest first, each time it changes.
  Stream<List<NetworkLogEntry>> watch() => _store.changes;
}
