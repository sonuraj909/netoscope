import 'graphql_details.dart';
import 'network_event_kind.dart';
import 'network_log_body.dart';
import 'network_log_error.dart';
import 'protocol_details.dart';
import 'webhook_details.dart';

/// The outcome category of a recorded event.
enum NetworkLogOutcome {
  /// Completed normally. For HTTP: a response with a status below 400.
  success,

  /// A response was received with an HTTP status code of 400 or above.
  httpError,

  /// The operation failed (timeout, connection failure, gRPC error status,
  /// failed connection, …). For HTTP exchanges: no response was received.
  failure,

  /// The operation was cancelled by the client.
  cancelled,
}

/// An immutable record of a network event: an HTTP call, a connection
/// lifecycle change or a single message on a long-lived connection.
///
/// Entries are produced by adapters and recorders after redaction and
/// truncation have been applied, so every value held here is safe to print,
/// store, display and export under the configured redaction rules.
///
/// HTTP calls use the defaults: [protocol] is [NetworkProtocol.http] and
/// [kind] is [NetworkEventKind.exchange]. For other protocols [method] holds
/// a short operation label (for example `WS` or `MQTT`) and [url] the
/// endpoint of the connection.
class NetworkLogEntry {
  /// Creates an entry. Collections are copied into unmodifiable views.
  NetworkLogEntry({
    required this.id,
    required String method,
    required this.url,
    required this.timestamp,
    Map<String, String> requestHeaders = const {},
    Map<String, String> responseHeaders = const {},
    this.requestBody,
    this.responseBody,
    this.statusCode,
    this.duration,
    this.error,
    this.requestSize,
    this.responseSize,
    this.protocol = NetworkProtocol.http,
    this.kind = NetworkEventKind.exchange,
    this.direction,
    this.lifecycle,
    this.connectionId,
    List<ProtocolDetails> details = const [],
    Map<String, String> metadata = const {},
  })  : method = method.toUpperCase(),
        requestHeaders = Map.unmodifiable(requestHeaders),
        responseHeaders = Map.unmodifiable(responseHeaders),
        details = List.unmodifiable(details),
        metadata = Map.unmodifiable(metadata);

  /// A unique identifier for this event.
  final String id;

  /// The upper-cased HTTP method, such as `GET`, or a protocol label.
  final String method;

  /// The full request or connection URL, including the (redacted) query.
  final Uri url;

  /// When the request was started or the event happened.
  final DateTime timestamp;

  /// Captured request (or handshake) headers. Empty when header capture is
  /// disabled.
  final Map<String, String> requestHeaders;

  /// Captured response headers. Empty when there was no response or header
  /// capture is disabled.
  final Map<String, String> responseHeaders;

  /// The captured request body, or the payload of an outgoing message.
  final NetworkLogBody? requestBody;

  /// The captured response body, or the payload of an incoming message.
  final NetworkLogBody? responseBody;

  /// The HTTP status code, or `null` when no HTTP response was received.
  final int? statusCode;

  /// For exchanges, the time until completion; for closed connections, how
  /// long the connection was open.
  final Duration? duration;

  /// Failure details, or `null` for events that completed normally.
  final NetworkLogError? error;

  /// Request (or outgoing message) size in bytes, when measurable.
  final int? requestSize;

  /// Response (or incoming message) size in bytes, when measurable.
  final int? responseSize;

  /// The protocol this event belongs to.
  final NetworkProtocol protocol;

  /// The shape of this event.
  final NetworkEventKind kind;

  /// For messages, which way the message travelled.
  final MessageDirection? direction;

  /// For connection events, the lifecycle stage.
  final ConnectionLifecycle? lifecycle;

  /// Groups the events of one long-lived connection.
  final String? connectionId;

  /// Protocol-specific information, such as [GraphQLDetails].
  final List<ProtocolDetails> details;

  /// Free-form, already-redacted metadata from adapters or recorders.
  final Map<String, String> metadata;

  /// The query parameters of [url]. Values have already been redacted.
  Map<String, List<String>> get queryParameters => url.queryParametersAll;

  /// Whether an HTTP response (of any status) was received.
  bool get hasResponse => statusCode != null;

  /// The first attached details of type [T], if any.
  T? detail<T extends ProtocolDetails>() {
    for (final item in details) {
      if (item is T) return item;
    }
    return null;
  }

  /// GraphQL information, when this call carried GraphQL operations.
  GraphQLDetails? get graphQL => detail<GraphQLDetails>();

  /// Webhook delivery information, when this call was a webhook delivery.
  WebhookDetails? get webhook => detail<WebhookDetails>();

  /// Whether a GraphQL response reported execution errors.
  bool get hasGraphQLErrors => graphQL?.hasErrors ?? false;

  /// The payload of a message event, whichever direction it travelled.
  NetworkLogBody? get messageBody =>
      direction == MessageDirection.outgoing ? requestBody : responseBody;

  /// The outcome category of this event.
  NetworkLogOutcome get outcome {
    if (error?.type == NetworkErrorType.cancelled) {
      return NetworkLogOutcome.cancelled;
    }
    final code = statusCode;
    if (code != null && code >= 400) return NetworkLogOutcome.httpError;
    if (error != null || lifecycle == ConnectionLifecycle.failed) {
      return NetworkLogOutcome.failure;
    }
    // An HTTP exchange without a response did not complete.
    if (code == null &&
        kind == NetworkEventKind.exchange &&
        protocol == NetworkProtocol.http) {
      return NetworkLogOutcome.failure;
    }
    return NetworkLogOutcome.success;
  }

  /// Whether the event completed normally.
  bool get isSuccess => outcome == NetworkLogOutcome.success;

  /// Whether [duration] meets or exceeds [threshold]. Only exchanges can be
  /// slow; connection lifetimes are not compared.
  bool isSlower(Duration threshold) {
    if (kind != NetworkEventKind.exchange) return false;
    final elapsed = duration;
    return elapsed != null && elapsed >= threshold;
  }

  /// A JSON-compatible representation of this entry.
  Map<String, Object?> toJson() => {
        'id': id,
        'protocol': protocol.name,
        'kind': kind.name,
        'method': method,
        'url': url.toString(),
        'timestamp': timestamp.toUtc().toIso8601String(),
        'statusCode': statusCode,
        'outcome': outcome.name,
        'durationMs': duration?.inMilliseconds,
        'direction': direction?.name,
        'lifecycle': lifecycle?.name,
        'connectionId': connectionId,
        'requestSize': requestSize,
        'responseSize': responseSize,
        'queryParameters': queryParameters,
        'requestHeaders': requestHeaders,
        'responseHeaders': responseHeaders,
        'requestBody': requestBody?.toJson(),
        'responseBody': responseBody?.toJson(),
        'error': error?.toJson(),
        'details': [for (final item in details) item.toJson()],
        'metadata': metadata,
      };

  @override
  String toString() =>
      'NetworkLogEntry($method $url → ${statusCode ?? outcome.name})';
}
