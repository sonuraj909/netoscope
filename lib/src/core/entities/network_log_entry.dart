import 'network_log_body.dart';
import 'network_log_error.dart';

/// The outcome category of a completed network call.
enum NetworkLogOutcome {
  /// A response was received with a status code below 400.
  success,

  /// A response was received with a status code of 400 or above.
  httpError,

  /// The call failed before a response was received
  /// (timeout, connection failure, certificate error, …).
  failure,

  /// The call was cancelled by the client.
  cancelled,
}

/// An immutable record of a single network call.
///
/// Entries are produced by the HTTP adapters after redaction and truncation
/// have been applied, so every value held here is safe to print, store,
/// display and export under the configured redaction rules.
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
  })  : method = method.toUpperCase(),
        requestHeaders = Map.unmodifiable(requestHeaders),
        responseHeaders = Map.unmodifiable(responseHeaders);

  /// A unique identifier for this call.
  final String id;

  /// The upper-cased HTTP method, such as `GET`.
  final String method;

  /// The full request URL, including the (redacted) query string.
  final Uri url;

  /// When the request was started.
  final DateTime timestamp;

  /// Captured request headers. Empty when header capture is disabled.
  final Map<String, String> requestHeaders;

  /// Captured response headers. Empty when there was no response or header
  /// capture is disabled.
  final Map<String, String> responseHeaders;

  /// The captured request body, or `null` when there was none or capture is
  /// disabled.
  final NetworkLogBody? requestBody;

  /// The captured response body, or `null` when there was none or capture is
  /// disabled.
  final NetworkLogBody? responseBody;

  /// The HTTP status code, or `null` when no response was received.
  final int? statusCode;

  /// Time from sending the request until the call completed, when measured.
  final Duration? duration;

  /// Failure details, or `null` for calls that completed normally.
  final NetworkLogError? error;

  /// Request payload size in bytes, when it could be measured safely.
  final int? requestSize;

  /// Response payload size in bytes, when it could be measured safely.
  final int? responseSize;

  /// The query parameters of [url]. Values have already been redacted.
  Map<String, List<String>> get queryParameters => url.queryParametersAll;

  /// Whether a response (of any status) was received.
  bool get hasResponse => statusCode != null;

  /// The outcome category of this call.
  NetworkLogOutcome get outcome {
    if (error?.type == NetworkErrorType.cancelled) {
      return NetworkLogOutcome.cancelled;
    }
    final code = statusCode;
    if (code == null) return NetworkLogOutcome.failure;
    if (code >= 400) return NetworkLogOutcome.httpError;
    return error == null
        ? NetworkLogOutcome.success
        : NetworkLogOutcome.failure;
  }

  /// Whether the call completed with a non-error response.
  bool get isSuccess => outcome == NetworkLogOutcome.success;

  /// Whether [duration] meets or exceeds [threshold].
  bool isSlower(Duration threshold) {
    final elapsed = duration;
    return elapsed != null && elapsed >= threshold;
  }

  /// A JSON-compatible representation of this entry.
  Map<String, Object?> toJson() => {
        'id': id,
        'method': method,
        'url': url.toString(),
        'timestamp': timestamp.toUtc().toIso8601String(),
        'statusCode': statusCode,
        'outcome': outcome.name,
        'durationMs': duration?.inMilliseconds,
        'requestSize': requestSize,
        'responseSize': responseSize,
        'queryParameters': queryParameters,
        'requestHeaders': requestHeaders,
        'responseHeaders': responseHeaders,
        'requestBody': requestBody?.toJson(),
        'responseBody': responseBody?.toJson(),
        'error': error?.toJson(),
      };

  @override
  String toString() =>
      'NetworkLogEntry($method $url → ${statusCode ?? outcome.name})';
}
