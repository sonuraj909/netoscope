import '../entities/network_log_entry.dart';

/// Saves and restores history between app launches.
///
/// Entries are already redacted, but they can still contain personal data:
/// only enable persistence where storing it on the device is acceptable.
abstract interface class NetworkLogPersistence {
  /// Loads saved entries, newest first. Returns an empty list when nothing
  /// is saved. Implementations should not throw for missing or corrupt data.
  Future<List<NetworkLogEntry>> load();

  /// Replaces the saved entries with [entries] (newest first).
  Future<void> save(List<NetworkLogEntry> entries);
}
