import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../security/body_capture.dart';
import '../log_capture.dart';

/// An HTTP call observed outside Dart (for example by native Android or iOS
/// code), to be recorded with `Netoscope.recordExternalCall`.
///
/// Values are raw; they are redacted, truncated and inspected (GraphQL,
/// gRPC-Web, webhooks) exactly like calls captured in Dart.
class ExternalNetworkCall {
  /// Creates a call description.
  const ExternalNetworkCall({
    required this.method,
    required this.url,
    required this.startedAt,
    this.duration,
    this.requestHeaders = const {},
    this.requestBody,
    this.statusCode,
    this.responseHeaders = const {},
    this.responseBody,
    this.error,
    this.errorType = NetworkErrorType.unknown,
    this.source = 'external',
    this.tags = const [],
  });

  /// The HTTP method.
  final String method;

  /// The request URL.
  final Uri url;

  /// When the request started.
  final DateTime startedAt;

  /// How long the call took.
  final Duration? duration;

  /// Request headers.
  final Map<String, String> requestHeaders;

  /// The request body: a `String` or bytes (`List<int>`).
  final Object? requestBody;

  /// The response status, if a response was received.
  final int? statusCode;

  /// Response headers.
  final Map<String, String> responseHeaders;

  /// The response body: a `String` or bytes (`List<int>`).
  final Object? responseBody;

  /// A failure description, if the call failed.
  final String? error;

  /// The failure category.
  final NetworkErrorType errorType;

  /// Where the call was observed, such as `android` or `ios`. Stored in the
  /// entry's metadata.
  final String source;

  /// Extra tags for this call.
  final List<String> tags;
}

String? _header(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

/// Records [call] through [capture].
void recordExternalCall(LogCapture capture, ExternalNetworkCall call) {
  capture.record(() {
    if (!capture.shouldLog(call.url)) return null;
    final requestType = _header(call.requestHeaders, 'content-type');
    final responseType = _header(call.responseHeaders, 'content-type');
    final message = call.error;
    final inspection = capture.inspectHttp(
      method: call.method,
      url: call.url,
      requestHeaders: call.requestHeaders,
      requestContentType: requestType,
      requestPayload: call.requestBody,
      statusCode: call.statusCode,
      responseContentType: responseType,
      responseHeaders: call.responseHeaders,
      responsePayload: call.responseBody,
      error: message == null ? null : capture.error(call.errorType, message),
    );
    int? size(Object? body) => BodyCapture.sizeOf(body);
    return NetworkLogEntry(
      id: capture.nextId(),
      method: call.method,
      url: capture.url(call.url),
      timestamp: call.startedAt,
      duration: call.duration,
      statusCode: call.statusCode,
      protocol: inspection.protocol,
      details: inspection.details,
      error: inspection.error,
      tags: capture.currentTags(call.tags),
      requestHeaders: capture.headers(call.requestHeaders),
      responseHeaders: capture.headers(call.responseHeaders),
      requestBody: capture.requestBody(
        (b) => b.capture(
          call.requestBody,
          context: capture.payload(
            call.url,
            MessageDirection.outgoing,
            contentType: requestType,
          ),
        ),
      ),
      responseBody: capture.responseBody(
        (b) => b.capture(
          call.responseBody,
          context: capture.payload(
            call.url,
            MessageDirection.incoming,
            contentType: responseType,
          ),
        ),
      ),
      requestSize: size(call.requestBody),
      responseSize: _header(call.responseHeaders, 'content-length') == null
          ? size(call.responseBody)
          : int.tryParse(_header(call.responseHeaders, 'content-length')!),
      metadata: {'source': call.source},
    );
  });
}
