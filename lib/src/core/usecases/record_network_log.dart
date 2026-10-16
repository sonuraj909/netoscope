import '../contracts/network_log_sink.dart';
import '../contracts/network_log_store.dart';
import '../entities/network_log_entry.dart';

/// Stores a completed entry and forwards it to every sink.
///
/// Sink failures are swallowed so that logging can never break a request.
class RecordNetworkLog {
  /// Creates the use case.
  RecordNetworkLog(this._store, {Iterable<NetworkLogSink> sinks = const []})
      : _sinks = List.unmodifiable(sinks);

  final NetworkLogStore _store;
  final List<NetworkLogSink> _sinks;

  /// Records [entry].
  void call(NetworkLogEntry entry) {
    _store.add(entry);
    for (final sink in _sinks) {
      try {
        sink.write(entry);
      } catch (_) {
        // A misbehaving sink must not affect the app's networking.
      }
    }
  }
}
