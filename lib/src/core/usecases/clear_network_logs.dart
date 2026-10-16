import '../contracts/network_log_store.dart';

/// Removes all recorded history.
class ClearNetworkLogs {
  /// Creates the use case.
  const ClearNetworkLogs(this._store);

  final NetworkLogStore _store;

  /// Clears the history.
  void call() => _store.clear();
}
