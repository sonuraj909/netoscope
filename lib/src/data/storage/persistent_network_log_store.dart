import 'dart:async';

import '../../core/contracts/network_log_persistence.dart';
import '../../core/contracts/network_log_store.dart';
import '../../core/entities/network_log_entry.dart';
import 'in_memory_network_log_store.dart';

/// A bounded store that survives app restarts.
///
/// Keeps history in memory like [InMemoryNetworkLogStore] and saves it
/// through a [NetworkLogPersistence] at most once per [saveDelay] after a
/// change. Pass it to `Netoscope(store: …)` and call [dispose] when done to
/// flush the last changes.
class PersistentNetworkLogStore implements NetworkLogStore {
  PersistentNetworkLogStore._(
    this._persistence,
    this._memory,
    this.saveDelay,
  ) {
    _subscription = _memory.changes.listen((_) => _scheduleSave());
  }

  /// Opens a store, restoring up to [maxEntries] saved entries.
  static Future<PersistentNetworkLogStore> open(
    NetworkLogPersistence persistence, {
    int maxEntries = 100,
    Duration saveDelay = const Duration(seconds: 1),
  }) async {
    final memory = InMemoryNetworkLogStore(maxEntries: maxEntries);
    List<NetworkLogEntry> saved;
    try {
      saved = await persistence.load();
    } catch (_) {
      saved = const [];
    }
    // Saved newest first; add oldest first so ordering is preserved.
    for (final entry in saved.take(maxEntries).toList().reversed) {
      memory.add(entry);
    }
    return PersistentNetworkLogStore._(persistence, memory, saveDelay);
  }

  final NetworkLogPersistence _persistence;
  final InMemoryNetworkLogStore _memory;
  late final StreamSubscription<List<NetworkLogEntry>> _subscription;
  Timer? _timer;
  Future<void> _pending = Future.value();

  /// The minimum time between saves.
  final Duration saveDelay;

  @override
  List<NetworkLogEntry> get entries => _memory.entries;

  @override
  Stream<List<NetworkLogEntry>> get changes => _memory.changes;

  @override
  void add(NetworkLogEntry entry) => _memory.add(entry);

  @override
  void clear() => _memory.clear();

  void _scheduleSave() {
    _timer ??= Timer(saveDelay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Saves the current history now.
  Future<void> flush() {
    final snapshot = _memory.entries;
    _pending = _pending.then((_) async {
      try {
        await _persistence.save(snapshot);
      } catch (_) {
        // Persistence is best-effort.
      }
    });
    return _pending;
  }

  /// Saves pending changes and releases resources.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _subscription.cancel();
    await flush();
    await _memory.dispose();
  }
}
