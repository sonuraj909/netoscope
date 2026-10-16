import 'dart:async';

import '../../core/contracts/network_activity_notifier.dart';
import '../../core/entities/network_log_entry.dart';

/// Keeps an [NetworkActivityNotifier] in sync with the history, sending at
/// most one update per [interval].
class ActivityNotificationController {
  /// Creates a controller reading history from [entries].
  ActivityNotificationController({
    required this.notifier,
    required List<NetworkLogEntry> Function() entries,
    bool Function()? isRecording,
    this.interval = const Duration(seconds: 1),
  })  : _entries = entries,
        _isRecording = isRecording ?? _always;

  static bool _always() => true;

  /// The notifier being updated.
  final NetworkActivityNotifier notifier;

  /// The minimum time between updates.
  final Duration interval;

  final List<NetworkLogEntry> Function() _entries;
  final bool Function() _isRecording;
  Timer? _timer;
  bool _active = false;

  /// Whether updates are sent.
  bool get isActive => _active;

  /// Starts (and shows the current state) or stops (and hides) updates.
  void setActive(bool active) {
    if (active == _active) return;
    _active = active;
    if (active) {
      _push();
    } else {
      _timer?.cancel();
      _timer = null;
      _safely(notifier.hide);
    }
  }

  /// Schedules an update after the history changed.
  void onHistoryChanged() {
    if (!_active || _timer != null) return;
    _timer = Timer(interval, () {
      _timer = null;
      if (_active) _push();
    });
  }

  /// Pushes the current state now (for example after recording was paused).
  void refresh() {
    if (!_active) return;
    _timer?.cancel();
    _timer = null;
    _push();
  }

  /// Stops updates and removes the notification.
  void dispose() => setActive(false);

  void _push() {
    final entries = _entries();
    if (entries.isEmpty) {
      _safely(notifier.hide);
      return;
    }
    final summary = NetworkActivitySummary(
      total: entries.length,
      failures: entries.where((e) => !e.isSuccess || e.hasGraphQLErrors).length,
      recent: entries.take(5).toList(),
      isRecording: _isRecording(),
    );
    _safely(() => notifier.show(summary));
  }

  static void _safely(Future<void> Function() action) {
    try {
      unawaited(action().catchError((Object _) {}));
    } catch (_) {
      // A failing notifier must never affect the app.
    }
  }
}
