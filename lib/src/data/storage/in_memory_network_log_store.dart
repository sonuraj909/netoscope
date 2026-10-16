import 'dart:async';
import 'dart:collection';

import '../../core/contracts/network_log_store.dart';
import '../../core/entities/network_log_entry.dart';

/// A bounded, in-memory [NetworkLogStore].
///
/// Keeps at most [maxEntries] entries; when full, the oldest entry is evicted.
/// Entries are ordered newest first by the time they were recorded.
class InMemoryNetworkLogStore implements NetworkLogStore {
  /// Creates a store that keeps up to [maxEntries] entries.
  InMemoryNetworkLogStore({this.maxEntries = 100})
      : assert(maxEntries > 0, 'maxEntries must be positive');

  /// The maximum number of retained entries.
  final int maxEntries;

  final ListQueue<NetworkLogEntry> _entries = ListQueue();
  final StreamController<List<NetworkLogEntry>> _changes =
      StreamController.broadcast();
  List<NetworkLogEntry>? _snapshot;

  @override
  List<NetworkLogEntry> get entries =>
      _snapshot ??= List.unmodifiable(_entries);

  @override
  Stream<List<NetworkLogEntry>> get changes => _changes.stream;

  @override
  void add(NetworkLogEntry entry) {
    if (_changes.isClosed) return;
    _entries.addFirst(entry);
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    _notify();
  }

  @override
  void clear() {
    if (_changes.isClosed || _entries.isEmpty) return;
    _entries.clear();
    _notify();
  }

  /// Releases the change stream. Later [add] and [clear] calls are ignored.
  Future<void> dispose() {
    _entries.clear();
    _snapshot = null;
    return _changes.close();
  }

  void _notify() {
    _snapshot = null;
    _changes.add(entries);
  }
}
