import 'dart:async';

import '../config/network_logger_config.dart';
import '../core/contracts/payload_decoder.dart';
import '../core/entities/network_event_kind.dart';
import '../core/entities/network_log_body.dart';
import '../core/entities/network_log_entry.dart';
import '../core/entities/network_log_error.dart';
import '../core/entities/protocol_details.dart';
import '../core/usecases/record_network_log.dart';
import '../protocols/graphql/graphql_inspector.dart';
import '../protocols/grpc/grpc_web_inspector.dart';
import '../protocols/webhook/webhook_config.dart';
import '../protocols/webhook/webhook_inspector.dart';
import '../security/body_capture.dart';
import '../security/log_redactor.dart';

/// The zone key holding tags set by `Netoscope.tagged`.
final Object netoscopeTagsZoneKey = Object();

/// Protocol information derived from an HTTP exchange.
typedef HttpInspection = ({
  NetworkProtocol protocol,
  List<ProtocolDetails> details,
  NetworkLogError? error,
});

/// Shared capture policy for the HTTP adapters.
///
/// Applies the configuration (exclusions, capture switches, redaction and
/// truncation) so each adapter only translates its client's types.
class LogCapture {
  /// Creates a capture policy that records into [record].
  LogCapture({required this.config, required RecordNetworkLog record})
      : _record = record,
        redactor = LogRedactor(
          extraKeys: config.sensitiveKeys,
          headerKeys: config.sensitiveHeaders,
          queryKeys: config.sensitiveQueryParameters,
          bodyKeys: config.sensitiveBodyKeys,
          mask: config.redactionMask,
        ) {
    _bodies = BodyCapture(
      redactor: redactor,
      maxSize: config.maxBodySize,
      decoders: config.payloadDecoders,
    );
    _graphQL = GraphQLInspector(
      redactor: redactor,
      maxTextLength: config.maxBodySize,
    );
    _grpc = GrpcWebInspector(redactor);
    _webhooks = WebhookInspector(config.webhooks);
  }

  /// The active configuration.
  final NetworkLoggerConfig config;

  /// The redactor built from [config].
  final LogRedactor redactor;

  final RecordNetworkLog _record;
  late final BodyCapture _bodies;
  late final GraphQLInspector _graphQL;
  late final GrpcWebInspector _grpc;
  late final WebhookInspector _webhooks;
  int _sequence = 0;

  /// Runtime pause switch. Nothing is recorded while this is `false`.
  bool recording = true;

  /// Whether new activity is recorded at all right now.
  bool get isRecording => config.isEnabled && recording;

  final Map<String, int> _claims = {};
  final Set<String> _globalTags = {};

  /// Tags applied to every call until removed.
  Set<String> get globalTags => Set.unmodifiable(_globalTags);

  /// Adds a global tag.
  void addTag(String tag) => _globalTags.add(tag);

  /// Removes a global tag.
  void removeTag(String tag) => _globalTags.remove(tag);

  /// Removes all global tags.
  void clearTags() => _globalTags.clear();

  /// Tags for a call starting now: global tags plus those of enclosing
  /// `Netoscope.tagged` zones, plus [extra].
  List<String> currentTags([Iterable<String> extra = const []]) {
    final zoneTags = Zone.current[netoscopeTagsZoneKey];
    return {
      ..._globalTags,
      if (zoneTags is Iterable<String>) ...zoneTags,
      ...extra,
    }.toList();
  }

  static String _claimKey(String method, Uri url) =>
      '${method.toUpperCase()} $url';

  /// Marks a call as recorded by a higher-level adapter (Dio, `http`) while
  /// it is being opened, so the `dart:io` layer does not record it again.
  void claim(String method, Uri url) {
    final key = _claimKey(method, url);
    _claims[key] = (_claims[key] ?? 0) + 1;
  }

  /// Ends a [claim].
  void release(String method, Uri url) {
    final key = _claimKey(method, url);
    final count = (_claims[key] ?? 0) - 1;
    if (count <= 0) {
      _claims.remove(key);
    } else {
      _claims[key] = count;
    }
  }

  /// Whether a higher-level adapter is currently recording this call.
  bool isClaimed(String method, Uri url) =>
      _claims.containsKey(_claimKey(method, url));

  /// Whether a call to [url] should be recorded.
  bool shouldLog(Uri url) => isRecording && !config.isExcluded(url);

  /// A new identifier, unique within this capture policy.
  String nextId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${(_sequence++).toRadixString(36)}';

  /// The redacted [url].
  Uri url(Uri url) => redactor.redactUrl(url);

  /// Redacted headers, or an empty map when header capture is disabled.
  ///
  /// Configured webhook signature headers are always masked.
  Map<String, String> headers(Map<String, String> headers) {
    if (!config.captureHeaders) return const {};
    final signatureHeaders = _webhooks.signatureHeaders;
    return {
      for (final entry in redactor.redactHeaders(headers).entries)
        entry.key: signatureHeaders.contains(entry.key.toLowerCase())
            ? redactor.mask
            : entry.value,
    };
  }

  /// The GraphQL inspector built from [config].
  GraphQLInspector get graphQL => _graphQL;

  /// Describes where a payload was seen, for [PayloadDecoder]s.
  PayloadContext payload(
    Uri url,
    MessageDirection direction, {
    String? contentType,
    NetworkProtocol protocol = NetworkProtocol.http,
  }) =>
      PayloadContext(
        contentType: contentType,
        url: url,
        direction: direction,
        protocol: protocol,
      );

  /// Recognizes GraphQL, gRPC-Web and webhook deliveries in an HTTP
  /// exchange. Payloads are the raw (unredacted) values; only redacted
  /// results are returned. Never throws.
  HttpInspection inspectHttp({
    required String method,
    required Uri url,
    required Map<String, String> requestHeaders,
    String? requestContentType,
    Object? requestPayload,
    int? statusCode,
    String? responseContentType,
    Map<String, String> responseHeaders = const {},
    Object? responsePayload,
    NetworkLogError? error,
    WebhookAttempt? webhookAttempt,
  }) {
    var protocol = NetworkProtocol.http;
    var resultError = error;
    final details = <ProtocolDetails>[];
    try {
      final grpc = _grpc.inspect(
        url: url,
        requestContentType: requestContentType,
        responseContentType: responseContentType,
        responseHeaders: responseHeaders,
        requestBytes: requestPayload is List<int> ? requestPayload : null,
        responseBytes: responsePayload is List<int> ? responsePayload : null,
      );
      if (grpc != null) {
        protocol = NetworkProtocol.grpc;
        details.add(grpc);
        resultError ??= GrpcWebInspector.errorFor(grpc);
      } else if (config.detectGraphQL) {
        final graphQL = _graphQL.inspectHttp(
          method: method,
          url: url,
          requestContentType: requestContentType,
          requestBody: requestPayload,
          responseBody: responsePayload,
        );
        if (graphQL != null) details.add(graphQL);
      }
    } catch (_) {
      // Protocol recognition is best-effort.
    }
    try {
      final webhook = _webhooks.inspect(
        url: url,
        requestHeaders: requestHeaders,
        attempt: webhookAttempt,
        statusCode: statusCode,
        error: resultError,
      );
      if (webhook != null) details.add(webhook);
    } catch (_) {
      // Webhook recognition is best-effort.
    }
    return (protocol: protocol, details: details, error: resultError);
  }

  /// The body capture policy, for adapter-specific payload types.
  BodyCapture get bodies => _bodies;

  /// A captured request body, or `null` when disabled or absent.
  NetworkLogBody? requestBody(
    NetworkLogBody? Function(BodyCapture bodies) capture,
  ) =>
      config.captureRequestBody ? _safely(() => capture(_bodies)) : null;

  /// A captured response body, or `null` when disabled or absent.
  NetworkLogBody? responseBody(
    NetworkLogBody? Function(BodyCapture bodies) capture,
  ) =>
      config.captureResponseBody ? _safely(() => capture(_bodies)) : null;

  /// An error description with a redacted [message].
  NetworkLogError error(NetworkErrorType type, String message) =>
      NetworkLogError(type: type, message: redactor.redactText(message));

  /// Builds and records an entry, swallowing any failure inside the logger.
  /// When [build] returns `null` nothing is recorded.
  void record(NetworkLogEntry? Function() build) {
    if (!isRecording) return;
    try {
      final entry = build();
      if (entry != null) _record(entry);
    } catch (_) {
      // Logging must never break or alter the app's networking.
    }
  }

  NetworkLogBody? _safely(NetworkLogBody? Function() capture) {
    try {
      return capture();
    } catch (_) {
      return const NetworkLogBody(
        kind: NetworkBodyKind.unsupported,
        content: '<body could not be captured>',
      );
    }
  }
}
