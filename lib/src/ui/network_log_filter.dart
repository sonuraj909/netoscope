import '../core/entities/network_event_kind.dart';
import '../core/entities/network_log_entry.dart';
import '../core/entities/payload_format.dart';
import '../core/entities/protocol_details.dart';
import '../core/entities/traffic_insights.dart';
import 'search_query.dart';

/// Status groups offered by the inspector's filter.
enum StatusFilter {
  /// Every event.
  all('All'),

  /// 2xx responses.
  success('2xx'),

  /// 3xx responses.
  redirect('3xx'),

  /// 4xx responses.
  clientError('4xx'),

  /// 5xx responses.
  serverError('5xx'),

  /// Failed or cancelled operations (no usable response).
  failed('Failed');

  const StatusFilter(this.label);

  /// A short label for the filter chip.
  final String label;

  /// Whether [entry] belongs to this group.
  bool matches(NetworkLogEntry entry) {
    final code = entry.statusCode;
    return switch (this) {
      StatusFilter.all => true,
      StatusFilter.success => code != null && code >= 200 && code < 300,
      StatusFilter.redirect => code != null && code >= 300 && code < 400,
      StatusFilter.clientError => code != null && code >= 400 && code < 500,
      StatusFilter.serverError => code != null && code >= 500,
      StatusFilter.failed => entry.outcome == NetworkLogOutcome.failure ||
          entry.outcome == NetworkLogOutcome.cancelled,
    };
  }
}

/// Relative time windows offered by the inspector.
enum TimeRangeFilter {
  /// No time restriction.
  all('Any time', null),

  /// The last minute.
  lastMinute('1 min', Duration(minutes: 1)),

  /// The last five minutes.
  lastFiveMinutes('5 min', Duration(minutes: 5)),

  /// The last fifteen minutes.
  lastFifteenMinutes('15 min', Duration(minutes: 15)),

  /// The last hour.
  lastHour('1 hour', Duration(hours: 1));

  const TimeRangeFilter(this.label, this.window);

  /// A short label for the filter chip.
  final String label;

  /// How far back to look, or `null` for no limit.
  final Duration? window;
}

/// An immutable set of inspector filters.
class NetworkLogFilter {
  /// Creates a filter. The defaults match every entry.
  const NetworkLogFilter({
    this.query = '',
    this.method,
    this.status = StatusFilter.all,
    this.onlySlow = false,
    this.protocols = const {},
    this.direction,
    this.sseEventType,
    this.payloadFormat,
    this.timeRange = TimeRangeFilter.all,
    this.onlyGraphQL = false,
    this.onlyGraphQLErrors = false,
    this.connectionId,
    this.tag,
    this.onlyDuplicates = false,
    this.onlyNPlusOne = false,
    this.ids,
  });

  /// The search box text: free text plus `key:value` filters (see
  /// [SearchQuery]), such as `method:POST status:>=400 duration:>500`.
  final String query;

  /// Only calls with this tag.
  final String? tag;

  /// Only calls detected as duplicates.
  final bool onlyDuplicates;

  /// Only calls in a detected N+1 burst.
  final bool onlyNPlusOne;

  /// Only these entries (for example one duplicate or N+1 group).
  final Set<String>? ids;

  /// The required HTTP method (or protocol label), or `null` for any.
  final String? method;

  /// The required status group.
  final StatusFilter status;

  /// Whether only exchanges at or above the slow threshold are kept.
  final bool onlySlow;

  /// The allowed protocols; empty allows all.
  final Set<NetworkProtocol> protocols;

  /// Only messages travelling this way, or `null` for any event.
  final MessageDirection? direction;

  /// Only SSE events of this type.
  final String? sseEventType;

  /// Only events whose request or response payload has this format.
  final PayloadFormat? payloadFormat;

  /// Only events within this time window.
  final TimeRangeFilter timeRange;

  /// Only calls carrying GraphQL operations.
  final bool onlyGraphQL;

  /// Only calls whose GraphQL response reported errors.
  final bool onlyGraphQLErrors;

  /// Only events of this connection.
  final String? connectionId;

  /// Whether any filter is active.
  bool get isActive => activeCount > 0 || query.trim().isNotEmpty;

  /// The number of active filters other than the search query, for badges.
  int get activeCount => [
        method != null,
        status != StatusFilter.all,
        onlySlow,
        protocols.isNotEmpty,
        direction != null,
        sseEventType != null,
        payloadFormat != null,
        timeRange != TimeRangeFilter.all,
        onlyGraphQL,
        onlyGraphQLErrors,
        connectionId != null,
        tag != null,
        onlyDuplicates,
        onlyNPlusOne,
        ids != null,
      ].where((active) => active).length;

  /// Returns a copy with the given fields replaced. The `clear…` flags reset
  /// nullable filters.
  NetworkLogFilter copyWith({
    String? query,
    String? method,
    bool clearMethod = false,
    StatusFilter? status,
    bool? onlySlow,
    Set<NetworkProtocol>? protocols,
    MessageDirection? direction,
    bool clearDirection = false,
    String? sseEventType,
    bool clearSseEventType = false,
    PayloadFormat? payloadFormat,
    bool clearPayloadFormat = false,
    TimeRangeFilter? timeRange,
    bool? onlyGraphQL,
    bool? onlyGraphQLErrors,
    String? connectionId,
    bool clearConnection = false,
    String? tag,
    bool clearTag = false,
    bool? onlyDuplicates,
    bool? onlyNPlusOne,
    Set<String>? ids,
    bool clearIds = false,
  }) =>
      NetworkLogFilter(
        query: query ?? this.query,
        method: clearMethod ? null : method ?? this.method,
        status: status ?? this.status,
        onlySlow: onlySlow ?? this.onlySlow,
        protocols: protocols ?? this.protocols,
        direction: clearDirection ? null : direction ?? this.direction,
        sseEventType:
            clearSseEventType ? null : sseEventType ?? this.sseEventType,
        payloadFormat:
            clearPayloadFormat ? null : payloadFormat ?? this.payloadFormat,
        timeRange: timeRange ?? this.timeRange,
        onlyGraphQL: onlyGraphQL ?? this.onlyGraphQL,
        onlyGraphQLErrors: onlyGraphQLErrors ?? this.onlyGraphQLErrors,
        connectionId:
            clearConnection ? null : connectionId ?? this.connectionId,
        tag: clearTag ? null : tag ?? this.tag,
        onlyDuplicates: onlyDuplicates ?? this.onlyDuplicates,
        onlyNPlusOne: onlyNPlusOne ?? this.onlyNPlusOne,
        ids: clearIds ? null : ids ?? this.ids,
      );

  SearchQuery get _search {
    final cached = _parsed[this];
    if (cached != null) return cached;
    return _parsed[this] = SearchQuery.parse(query);
  }

  static final Expando<SearchQuery> _parsed = Expando('netoscope.query');

  /// Whether [entry] passes every filter. [now] anchors [timeRange];
  /// [insights] answers duplicate and N+1 filters.
  bool matches(
    NetworkLogEntry entry, {
    required Duration slowThreshold,
    DateTime? now,
    TrafficInsights? insights,
  }) {
    final search = _search;
    if (!search.isEmpty &&
        !search.matches(
          entry,
          SearchContext(slowThreshold: slowThreshold, insights: insights),
        )) {
      return false;
    }
    if (method != null && entry.method != method) return false;
    if (!status.matches(entry)) return false;
    if (onlySlow && !entry.isSlower(slowThreshold)) return false;
    if (protocols.isNotEmpty && !protocols.contains(entry.protocol)) {
      return false;
    }
    if (direction != null && entry.direction != direction) return false;
    if (sseEventType != null &&
        entry.detail<SseDetails>()?.eventType != sseEventType) {
      return false;
    }
    if (payloadFormat != null &&
        entry.requestBody?.format != payloadFormat &&
        entry.responseBody?.format != payloadFormat) {
      return false;
    }
    final window = timeRange.window;
    if (window != null &&
        entry.timestamp.isBefore((now ?? DateTime.now()).subtract(window))) {
      return false;
    }
    if (onlyGraphQL && entry.graphQL == null) return false;
    if (onlyGraphQLErrors && !entry.hasGraphQLErrors) return false;
    if (connectionId != null && entry.connectionId != connectionId) {
      return false;
    }
    if (tag != null && !entry.tags.contains(tag)) return false;
    if (ids != null && !ids!.contains(entry.id)) return false;
    if (onlyDuplicates &&
        !(insights?.duplicateIds.contains(entry.id) ?? false)) {
      return false;
    }
    if (onlyNPlusOne && !(insights?.nPlusOneIds.contains(entry.id) ?? false)) {
      return false;
    }
    return true;
  }

  /// The entries that pass every filter, in their original order.
  List<NetworkLogEntry> apply(
    Iterable<NetworkLogEntry> entries, {
    required Duration slowThreshold,
    DateTime? now,
    TrafficInsights? insights,
  }) {
    final anchor = now ?? DateTime.now();
    return [
      for (final entry in entries)
        if (matches(
          entry,
          slowThreshold: slowThreshold,
          now: anchor,
          insights: insights,
        ))
          entry,
    ];
  }

  /// The lower-case text that free-text search terms are matched against.
  static String searchText(NetworkLogEntry entry) =>
      SearchQuery.searchText(entry);
}
