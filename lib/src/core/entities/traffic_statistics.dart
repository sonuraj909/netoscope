import '../usecases/analyze_traffic.dart';
import 'network_event_kind.dart';
import 'network_log_entry.dart';

/// Per-endpoint aggregate.
class EndpointStatistics {
  /// Creates an aggregate.
  const EndpointStatistics({
    required this.pattern,
    required this.calls,
    required this.failures,
    required this.averageDuration,
  });

  /// The endpoint pattern, such as `GET api.dev/users/{id}`.
  final String pattern;

  /// The number of calls.
  final int calls;

  /// How many failed.
  final int failures;

  /// The average duration of calls with a known duration.
  final Duration? averageDuration;
}

/// Aggregate numbers for a history.
class TrafficStatistics {
  TrafficStatistics._({
    required this.totalEvents,
    required this.exchanges,
    required this.successes,
    required this.httpErrors,
    required this.failures,
    required this.cancelled,
    required this.slow,
    required this.bytesSent,
    required this.bytesReceived,
    required this.averageDuration,
    required this.medianDuration,
    required this.p95Duration,
    required this.maxDuration,
    required this.byStatusClass,
    required this.byMethod,
    required this.byProtocol,
    required this.byHost,
    required this.slowestEndpoints,
    required this.busiestEndpoints,
    required this.first,
    required this.last,
  });

  /// Computes statistics for [entries]. Exchanges are HTTP-style calls;
  /// connection and message events count towards [totalEvents] and
  /// [byProtocol] only.
  factory TrafficStatistics.from(
    Iterable<NetworkLogEntry> entries, {
    Duration slowThreshold = const Duration(seconds: 3),
  }) {
    final all = entries.toList();
    final exchanges = [
      for (final e in all)
        if (e.kind == NetworkEventKind.exchange) e,
    ];
    final durations = [
      for (final e in exchanges)
        if (e.duration != null) e.duration!,
    ]..sort();

    Duration? percentile(double p) {
      if (durations.isEmpty) return null;
      final index = ((durations.length - 1) * p).round();
      return durations[index];
    }

    final statusClass = <String, int>{};
    for (final e in exchanges) {
      final code = e.statusCode;
      final key = code == null ? 'Failed' : '${code ~/ 100}xx';
      statusClass[key] = (statusClass[key] ?? 0) + 1;
    }

    Map<String, int> countBy(Iterable<String> keys) {
      final counts = <String, int>{};
      for (final key in keys) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return Map.fromEntries(sorted);
    }

    final endpoints = <String, List<NetworkLogEntry>>{};
    for (final e in exchanges) {
      (endpoints[TrafficAnalyzer.endpointPattern(e)] ??= []).add(e);
    }
    final endpointStats = [
      for (final MapEntry(key: pattern, value: calls) in endpoints.entries)
        EndpointStatistics(
          pattern: pattern,
          calls: calls.length,
          failures: calls.where((e) => !e.isSuccess).length,
          averageDuration: _average([
            for (final e in calls)
              if (e.duration != null) e.duration!,
          ]),
        ),
    ];

    final timestamps = [for (final e in all) e.timestamp]..sort();
    return TrafficStatistics._(
      totalEvents: all.length,
      exchanges: exchanges.length,
      successes:
          exchanges.where((e) => e.outcome == NetworkLogOutcome.success).length,
      httpErrors: exchanges
          .where((e) => e.outcome == NetworkLogOutcome.httpError)
          .length,
      failures:
          exchanges.where((e) => e.outcome == NetworkLogOutcome.failure).length,
      cancelled: exchanges
          .where((e) => e.outcome == NetworkLogOutcome.cancelled)
          .length,
      slow: exchanges.where((e) => e.isSlower(slowThreshold)).length,
      bytesSent: all.fold(0, (sum, e) => sum + (e.requestSize ?? 0)),
      bytesReceived: all.fold(0, (sum, e) => sum + (e.responseSize ?? 0)),
      averageDuration: _average(durations),
      medianDuration: percentile(0.5),
      p95Duration: percentile(0.95),
      maxDuration: durations.isEmpty ? null : durations.last,
      byStatusClass: Map.unmodifiable(statusClass),
      byMethod: Map.unmodifiable(countBy(exchanges.map((e) => e.method))),
      byProtocol: Map.unmodifiable(countBy(all.map((e) => e.protocol.label))),
      byHost: Map.unmodifiable(countBy(all.map((e) => e.url.host))),
      slowestEndpoints: List.unmodifiable(
        ([
          ...endpointStats.where((e) => e.averageDuration != null)
        ]..sort((a, b) => b.averageDuration!.compareTo(a.averageDuration!)))
            .take(5),
      ),
      busiestEndpoints: List.unmodifiable(
        ([...endpointStats]..sort((a, b) => b.calls.compareTo(a.calls)))
            .take(5),
      ),
      first: timestamps.isEmpty ? null : timestamps.first,
      last: timestamps.isEmpty ? null : timestamps.last,
    );
  }

  static Duration? _average(List<Duration> durations) => durations.isEmpty
      ? null
      : Duration(
          microseconds:
              durations.fold<int>(0, (s, d) => s + d.inMicroseconds) ~/
                  durations.length,
        );

  /// All recorded events, including connection and message events.
  final int totalEvents;

  /// Request/response exchanges.
  final int exchanges;

  /// Exchanges that succeeded.
  final int successes;

  /// Exchanges with an HTTP status of 400 or above.
  final int httpErrors;

  /// Exchanges that failed without a usable response.
  final int failures;

  /// Exchanges cancelled by the client.
  final int cancelled;

  /// Exchanges at or above the slow threshold.
  final int slow;

  /// Bytes sent, where measurable.
  final int bytesSent;

  /// Bytes received, where measurable.
  final int bytesReceived;

  /// The mean exchange duration.
  final Duration? averageDuration;

  /// The median exchange duration.
  final Duration? medianDuration;

  /// The 95th-percentile exchange duration.
  final Duration? p95Duration;

  /// The longest exchange duration.
  final Duration? maxDuration;

  /// Exchange counts by `2xx`, `3xx`, `4xx`, `5xx` and `Failed`.
  final Map<String, int> byStatusClass;

  /// Exchange counts by method, most frequent first.
  final Map<String, int> byMethod;

  /// Event counts by protocol, most frequent first.
  final Map<String, int> byProtocol;

  /// Event counts by host, most frequent first.
  final Map<String, int> byHost;

  /// Up to five endpoint patterns with the highest average duration.
  final List<EndpointStatistics> slowestEndpoints;

  /// Up to five most-called endpoint patterns.
  final List<EndpointStatistics> busiestEndpoints;

  /// The earliest event time.
  final DateTime? first;

  /// The latest event time.
  final DateTime? last;

  /// The share of exchanges that succeeded, between 0 and 1.
  double? get successRate => exchanges == 0 ? null : successes / exchanges;
}
