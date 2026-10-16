import '../entities/network_log_entry.dart';

/// A snapshot of recent network activity for a notification.
class NetworkActivitySummary {
  /// Creates a summary.
  NetworkActivitySummary({
    required this.total,
    required this.failures,
    required List<NetworkLogEntry> recent,
    this.isRecording = true,
  }) : recent = List.unmodifiable(recent);

  /// The number of recorded events.
  final int total;

  /// How many of them failed (HTTP errors, failures, cancellations or
  /// GraphQL errors).
  final int failures;

  /// The most recent events, newest first (at most five).
  final List<NetworkLogEntry> recent;

  /// Whether recording is on; `false` while paused.
  final bool isRecording;

  /// The most recent event, if any.
  NetworkLogEntry? get latest => recent.isEmpty ? null : recent.first;

  /// A short title, such as `Netoscope · 12 requests`.
  String get title =>
      'Netoscope · $total ${total == 1 ? 'request' : 'requests'}';

  /// One line per recent event, such as `POST 200 /auth/login`.
  List<String> get lines => [
        for (final entry in recent)
          '${entry.method} '
              '${entry.statusCode ?? entry.outcome.name.toUpperCase()} '
              '${entry.url.path.isEmpty ? '/' : entry.url.path}',
      ];

  /// A one-line description for compact notifications.
  String get body {
    final latest = lines.isEmpty ? 'No requests yet' : lines.first;
    return failures == 0 ? latest : '$latest · $failures failed';
  }
}

/// Shows network activity outside the app UI, typically as a local
/// notification that opens the inspector when tapped.
///
/// Netoscope calls [show] with a fresh summary (at most once per update
/// interval) and [hide] when notifications are switched off or the history
/// is cleared. Implementations must not throw.
///
/// `package:netoscope_notifications` provides an implementation based on
/// `flutter_local_notifications`.
abstract interface class NetworkActivityNotifier {
  /// Shows or updates the notification.
  Future<void> show(NetworkActivitySummary summary);

  /// Removes the notification.
  Future<void> hide();
}
