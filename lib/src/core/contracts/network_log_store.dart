import '../entities/network_log_entry.dart';

/// Holds the history of recorded network calls.
abstract interface class NetworkLogStore {
  /// Adds [entry] to the history.
  void add(NetworkLogEntry entry);

  /// A snapshot of the history, newest first. The list is unmodifiable.
  List<NetworkLogEntry> get entries;

  /// Emits a fresh snapshot (newest first) whenever the history changes,
  /// including after [clear]. Does not replay the current state; read
  /// [entries] for that.
  Stream<List<NetworkLogEntry>> get changes;

  /// Removes every entry.
  void clear();
}
