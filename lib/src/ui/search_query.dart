import '../core/entities/graphql_details.dart';
import '../core/entities/network_event_kind.dart';
import '../core/entities/network_log_entry.dart';
import '../core/entities/protocol_details.dart';
import '../core/entities/traffic_insights.dart';

/// Context needed by some search terms.
class SearchContext {
  /// Creates a context.
  SearchContext({required this.slowThreshold, TrafficInsights? insights})
      : insights = insights ?? TrafficInsights.empty;

  /// Calls at least this slow match `is:slow`.
  final Duration slowThreshold;

  /// Duplicate and N+1 findings for `is:duplicate` and `is:n+1`.
  final TrafficInsights insights;
}

typedef _Predicate = bool Function(
    NetworkLogEntry entry, SearchContext context);

/// A parsed inspector search, combining free text with `key:value` filters.
///
/// All terms must match. Within one term, comma-separated values are
/// alternatives (`method:GET,POST`). Prefix a term with `-` or `!` to negate
/// it. Quote values containing spaces (`body:"not found"`).
///
/// | Key | Examples |
/// | --- | --- |
/// | `method:` | `method:POST`, `method:get,put` |
/// | `status:` | `status:404`, `status:4xx`, `status:>=500`, `status:200-299`, `status:error`, `status:ok` |
/// | `host:` / `path:` / `url:` | `host:api.dev`, `path:/users` |
/// | `duration:` | `duration:>500`, `duration:>=1s`, `duration:100-300ms` |
/// | `size:` | `size:>10kb`, `size:<1mb` (response size) |
/// | `protocol:` | `protocol:ws`, `protocol:sse,grpc` |
/// | `tag:` | `tag:login-flow` |
/// | `is:` | `is:slow`, `is:error`, `is:graphql`, `is:duplicate`, `is:n+1`, `is:cancelled`, `is:message`, `is:webhook` |
/// | `op:` | `op:GetUser` (GraphQL operation) |
/// | `header:` | `header:authorization` (request or response header name) |
/// | `body:` | `body:token` (request or response body) |
/// | `event:` / `topic:` / `source:` | SSE event type, MQTT topic, external source |
class SearchQuery {
  SearchQuery._(this.input, this._terms, this.unknownKeys);

  /// Parses [input].
  factory SearchQuery.parse(String input) {
    final terms = <_Predicate>[];
    final unknown = <String>[];
    for (final match in _token.allMatches(input)) {
      final negated = match.group(1)!.isNotEmpty;
      final key = match.group(2)?.toLowerCase();
      final raw = match.group(3) ?? match.group(4)!;
      final value = _unquote(raw);
      if (value.isEmpty) continue;
      _Predicate? predicate;
      if (key != null) {
        predicate = _filter(key, value);
        if (predicate == null) unknown.add(key);
      }
      // Unknown keys and plain words are free text.
      predicate ??= _text(key == null ? value : '$key:$value');
      final positive = predicate;
      terms.add(
        negated ? (e, c) => !positive(e, c) : positive,
      );
    }
    return SearchQuery._(input, terms, List.unmodifiable(unknown));
  }

  /// An empty query, matching everything.
  static final SearchQuery empty = SearchQuery._('', const [], const []);

  /// The original text.
  final String input;

  /// Keys that were not recognized (treated as free text).
  final List<String> unknownKeys;

  final List<_Predicate> _terms;

  /// Whether the query has any terms.
  bool get isEmpty => _terms.isEmpty;

  /// Whether [entry] matches every term.
  bool matches(NetworkLogEntry entry, SearchContext context) =>
      _terms.every((term) => term(entry, context));

  static final RegExp _token = RegExp(
    r'''([-!]?)(?:([A-Za-z]+):("[^"]*"|\S+)|("[^"]*"|\S+))''',
  );

  static String _unquote(String value) =>
      value.length >= 2 && value.startsWith('"') && value.endsWith('"')
          ? value.substring(1, value.length - 1)
          : value;

  static List<String> _alternatives(String value) => [
        for (final part in value.split(','))
          if (part.trim().isNotEmpty) part.trim().toLowerCase(),
      ];

  static _Predicate _text(String value) {
    final needle = value.toLowerCase();
    return (entry, _) => searchText(entry).contains(needle);
  }

  static _Predicate? _filter(String key, String value) {
    final alts = _alternatives(value);
    bool anyAlt(bool Function(String alt) test) => alts.any(test);
    switch (key) {
      case 'method' || 'm':
        return (e, _) => anyAlt((a) => e.method.toLowerCase() == a);
      case 'status' || 's':
        return (e, _) => anyAlt((a) => _status(e, a));
      case 'host' || 'h':
        return (e, _) => anyAlt((a) => e.url.host.toLowerCase().contains(a));
      case 'path' || 'p':
        return (e, _) => anyAlt((a) => e.url.path.toLowerCase().contains(a));
      case 'url' || 'u':
        return (e, _) =>
            anyAlt((a) => e.url.toString().toLowerCase().contains(a));
      case 'duration' || 'd' || 'time':
        final range = _NumberRange.parse(value, _durationUnits, 'ms');
        if (range == null) return null;
        return (e, _) {
          final ms = e.duration?.inMicroseconds;
          return ms != null && range.contains(ms / 1000);
        };
      case 'size':
        final range = _NumberRange.parse(value, _sizeUnits, 'b');
        if (range == null) return null;
        return (e, _) {
          final size = e.responseSize;
          return size != null && range.contains(size.toDouble());
        };
      case 'protocol' || 'proto':
        return (e, _) => anyAlt((a) => _protocol(e.protocol, a));
      case 'tag' || 't':
        return (e, _) => anyAlt(
              (a) => e.tags.any((tag) => tag.toLowerCase() == a),
            );
      case 'is':
        return (e, c) => anyAlt((a) => _is(e, c, a));
      case 'op' || 'operation':
        return (e, _) => anyAlt(
              (a) =>
                  e.graphQL?.operations.any(
                    (op) => (op.name ?? '').toLowerCase().contains(a),
                  ) ??
                  false,
            );
      case 'header':
        return (e, _) => anyAlt(
              (a) => [...e.requestHeaders.keys, ...e.responseHeaders.keys]
                  .any((name) => name.toLowerCase().contains(a)),
            );
      case 'body':
        return (e, _) => anyAlt(
              (a) => [e.requestBody?.content, e.responseBody?.content]
                  .any((body) => body?.toLowerCase().contains(a) ?? false),
            );
      case 'event':
        return (e, _) => anyAlt(
              (a) => e.detail<SseDetails>()?.eventType.toLowerCase() == a,
            );
      case 'topic':
        return (e, _) => anyAlt(
              (a) =>
                  e.detail<MqttDetails>()?.topic?.toLowerCase().contains(a) ??
                  false,
            );
      case 'source':
        return (e, _) =>
            anyAlt((a) => e.metadata['source']?.toLowerCase() == a);
    }
    return null;
  }

  static bool _status(NetworkLogEntry e, String alt) {
    final code = e.statusCode;
    switch (alt) {
      case 'ok' || 'success':
        return e.outcome == NetworkLogOutcome.success;
      case 'error' || 'failed' || 'fail' || 'failure':
        return e.outcome != NetworkLogOutcome.success;
      case 'cancelled' || 'canceled':
        return e.outcome == NetworkLogOutcome.cancelled;
    }
    if (code == null) return false;
    final klass = RegExp(r'^([1-5])xx$').firstMatch(alt);
    if (klass != null) return code ~/ 100 == int.parse(klass.group(1)!);
    final range = _NumberRange.parse(alt, const {'': 1}, '');
    return range != null && range.contains(code.toDouble());
  }

  static bool _protocol(NetworkProtocol protocol, String alt) => switch (alt) {
        'http' || 'https' => protocol == NetworkProtocol.http,
        'ws' || 'wss' || 'websocket' => protocol == NetworkProtocol.webSocket,
        'sse' => protocol == NetworkProtocol.sse,
        'grpc' => protocol == NetworkProtocol.grpc,
        'mqtt' => protocol == NetworkProtocol.mqtt,
        'other' => protocol == NetworkProtocol.other,
        _ => false,
      };

  static bool _is(NetworkLogEntry e, SearchContext c, String alt) =>
      switch (alt) {
        'slow' => e.isSlower(c.slowThreshold),
        'error' ||
        'failed' ||
        'failure' =>
          e.outcome != NetworkLogOutcome.success || e.hasGraphQLErrors,
        'success' ||
        'ok' =>
          e.outcome == NetworkLogOutcome.success && !e.hasGraphQLErrors,
        'cancelled' || 'canceled' => e.outcome == NetworkLogOutcome.cancelled,
        'graphql' || 'gql' => e.graphQL != null,
        'duplicate' ||
        'dup' ||
        'duplicates' =>
          c.insights.duplicateIds.contains(e.id),
        'n+1' || 'nplus1' || 'n1' => c.insights.nPlusOneIds.contains(e.id),
        'message' || 'msg' => e.kind == NetworkEventKind.message,
        'connection' || 'conn' => e.kind == NetworkEventKind.connection,
        'exchange' || 'call' => e.kind == NetworkEventKind.exchange,
        'webhook' => e.webhook != null,
        'tagged' => e.tags.isNotEmpty,
        _ => false,
      };

  static const Map<String, double> _durationUnits = {
    'us': 0.001,
    'ms': 1,
    's': 1000,
    'm': 60000,
  };

  static const Map<String, double> _sizeUnits = {
    'b': 1,
    'kb': 1024,
    'k': 1024,
    'mb': 1024 * 1024,
    'm': 1024 * 1024,
  };

  /// The lower-case text that free-text terms are matched against: the URL,
  /// GraphQL operations, SSE event types, MQTT topics, gRPC methods and tags.
  static String searchText(NetworkLogEntry entry) {
    final buffer = StringBuffer('${entry.method} ${entry.url}');
    for (final details in entry.details) {
      switch (details) {
        case GraphQLDetails(:final operations):
          for (final op in operations) {
            buffer.write(' ${op.type.name} ${op.name ?? ''}');
          }
        case SseDetails(:final eventType):
          buffer.write(' $eventType');
        case MqttDetails(:final topic):
          buffer.write(' ${topic ?? ''}');
        case GrpcDetails(:final service, :final method):
          buffer.write(' $service/$method');
      }
    }
    for (final tag in entry.tags) {
      buffer.write(' #$tag');
    }
    return buffer.toString().toLowerCase();
  }
}

/// A numeric comparison: `>5`, `>=5`, `<5`, `<=5`, `=5`, `5`, or `5-10`,
/// with optional units.
class _NumberRange {
  const _NumberRange(this.min, this.max,
      {this.minInclusive = true, this.maxInclusive = true});

  final double? min;
  final double? max;
  final bool minInclusive;
  final bool maxInclusive;

  bool contains(double value) {
    final min = this.min;
    final max = this.max;
    final tooLow = min != null && (minInclusive ? value < min : value <= min);
    final tooHigh = max != null && (maxInclusive ? value > max : value >= max);
    return !tooLow && !tooHigh;
  }

  static final RegExp _comparison =
      RegExp(r'^(>=|<=|>|<|=)?\s*([\d.]+)\s*([a-z]*)$');
  static final RegExp _between =
      RegExp(r'^([\d.]+)\s*([a-z]*)\s*-\s*([\d.]+)\s*([a-z]*)$');

  static _NumberRange? parse(
    String input,
    Map<String, double> units,
    String defaultUnit,
  ) {
    final text = input.trim().toLowerCase();
    double? scale(String number, String unit) {
      final value = double.tryParse(number);
      final factor = units[unit.isEmpty ? defaultUnit : unit];
      return value == null || factor == null ? null : value * factor;
    }

    final between = _between.firstMatch(text);
    if (between != null) {
      final unit = between.group(4)!;
      final low = scale(between.group(1)!,
          between.group(2)!.isEmpty ? unit : between.group(2)!);
      final high = scale(between.group(3)!, unit);
      return low == null || high == null ? null : _NumberRange(low, high);
    }
    final match = _comparison.firstMatch(text);
    if (match == null) return null;
    final value = scale(match.group(2)!, match.group(3)!);
    if (value == null) return null;
    return switch (match.group(1)) {
      '>' => _NumberRange(value, null, minInclusive: false),
      '>=' => _NumberRange(value, null),
      '<' => _NumberRange(null, value, maxInclusive: false),
      '<=' => _NumberRange(null, value),
      _ => _NumberRange(value, value),
    };
  }
}
