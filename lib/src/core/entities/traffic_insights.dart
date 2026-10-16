import 'network_log_entry.dart';

/// Calls that look redundant: exact repeats, or an N+1 burst.
class RequestGroup {
  /// Creates a group. [entries] are ordered oldest first.
  RequestGroup({required this.pattern, required List<NetworkLogEntry> entries})
      : entries = List.unmodifiable(entries);

  /// What the calls have in common, such as `GET api.dev/users/{id}`.
  final String pattern;

  /// The calls, oldest first.
  final List<NetworkLogEntry> entries;

  /// How many calls are in the group.
  int get count => entries.length;

  /// Time from the first to the last call's start.
  Duration get span =>
      entries.last.timestamp.difference(entries.first.timestamp);
}

/// Redundant-traffic findings for a history.
class TrafficInsights {
  /// Creates insights.
  TrafficInsights({
    List<RequestGroup> duplicates = const [],
    List<RequestGroup> nPlusOne = const [],
  })  : duplicates = List.unmodifiable(duplicates),
        nPlusOne = List.unmodifiable(nPlusOne),
        duplicateIds = {
          for (final group in duplicates)
            for (final entry in group.entries) entry.id,
        },
        nPlusOneIds = {
          for (final group in nPlusOne)
            for (final entry in group.entries) entry.id,
        };

  /// No findings.
  static final TrafficInsights empty = TrafficInsights();

  /// Identical requests (method, URL and body) repeated within a short
  /// window.
  final List<RequestGroup> duplicates;

  /// Bursts of requests to one endpoint pattern that differ only by an ID,
  /// typical of loading a list and then each item separately.
  final List<RequestGroup> nPlusOne;

  /// IDs of entries in [duplicates].
  final Set<String> duplicateIds;

  /// IDs of entries in [nPlusOne].
  final Set<String> nPlusOneIds;

  /// Whether anything was found.
  bool get isEmpty => duplicates.isEmpty && nPlusOne.isEmpty;
}
