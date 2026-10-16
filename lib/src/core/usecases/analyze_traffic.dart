import '../entities/network_event_kind.dart';
import '../entities/network_log_entry.dart';
import '../entities/traffic_insights.dart';

/// Detects duplicate requests and N+1 request patterns.
class TrafficAnalyzer {
  /// Creates an analyzer.
  ///
  /// Calls belong to one burst when each starts within [window] of the
  /// previous one. A burst of identical calls is reported when it has at
  /// least [duplicateThreshold] calls; a burst of calls to one endpoint
  /// pattern with different IDs when it has at least [nPlusOneThreshold].
  const TrafficAnalyzer({
    this.window = const Duration(seconds: 2),
    this.duplicateThreshold = 2,
    this.nPlusOneThreshold = 5,
  });

  /// The maximum gap between calls in one burst.
  final Duration window;

  /// The minimum number of identical calls reported as duplicates.
  final int duplicateThreshold;

  /// The minimum number of calls reported as an N+1 pattern.
  final int nPlusOneThreshold;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _numeric = RegExp(r'^\d+$');
  static final RegExp _hexId = RegExp(r'^[0-9a-f]{8,}$', caseSensitive: false);
  static final RegExp _token = RegExp(r'^(?=.*\d)(?=.*[A-Za-z])[\w-]{16,}$');

  /// Whether a path segment looks like an identifier.
  static bool isIdSegment(String segment) =>
      _numeric.hasMatch(segment) ||
      _uuid.hasMatch(segment) ||
      (_hexId.hasMatch(segment) && segment.contains(RegExp(r'\d'))) ||
      _token.hasMatch(segment);

  /// The endpoint pattern of [entry], such as `GET api.dev/users/{id}`.
  /// Query values are ignored; query keys are kept.
  static String endpointPattern(NetworkLogEntry entry) {
    final url = entry.url;
    final path = [
      for (final segment in url.pathSegments)
        isIdSegment(segment) ? '{id}' : segment,
    ].join('/');
    final keys = url.queryParameters.keys.toList()..sort();
    final query = keys.isEmpty ? '' : '?${keys.join('&')}';
    return '${entry.method} ${url.host}/$path$query';
  }

  /// Analyzes [entries] (any order).
  TrafficInsights analyze(Iterable<NetworkLogEntry> entries) {
    final exchanges = [
      for (final entry in entries)
        if (entry.kind == NetworkEventKind.exchange) entry,
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final byRequest = <String, List<NetworkLogEntry>>{};
    final byPattern = <String, List<NetworkLogEntry>>{};
    for (final entry in exchanges) {
      final request = '${entry.method} ${entry.url}\n'
          '${entry.requestBody?.content ?? ''}';
      (byRequest[request] ??= []).add(entry);
      (byPattern[endpointPattern(entry)] ??= []).add(entry);
    }

    final duplicates = [
      for (final group in byRequest.values)
        for (final burst in _bursts(group))
          if (burst.length >= duplicateThreshold)
            RequestGroup(
              pattern: '${burst.first.method} ${burst.first.url}',
              entries: burst,
            ),
    ];
    final nPlusOne = [
      for (final MapEntry(key: pattern, value: group) in byPattern.entries)
        for (final burst in _bursts(group))
          if (burst.length >= nPlusOneThreshold &&
              {for (final e in burst) e.url}.length >= nPlusOneThreshold)
            RequestGroup(pattern: pattern, entries: burst),
    ];
    int byCount(RequestGroup a, RequestGroup b) => b.count.compareTo(a.count);
    return TrafficInsights(
      duplicates: duplicates..sort(byCount),
      nPlusOne: nPlusOne..sort(byCount),
    );
  }

  Iterable<List<NetworkLogEntry>> _bursts(List<NetworkLogEntry> sorted) sync* {
    var burst = <NetworkLogEntry>[];
    for (final entry in sorted) {
      if (burst.isNotEmpty &&
          entry.timestamp.difference(burst.last.timestamp) > window) {
        yield burst;
        burst = [];
      }
      burst.add(entry);
    }
    if (burst.isNotEmpty) yield burst;
  }
}
