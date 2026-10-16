import '../config/network_logger_config.dart';
import '../core/entities/network_log_body.dart';
import '../core/entities/network_log_entry.dart';
import '../core/entities/network_log_error.dart';
import '../core/usecases/record_network_log.dart';
import '../security/body_capture.dart';
import '../security/log_redactor.dart';

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
          mask: config.redactionMask,
        ) {
    _bodies = BodyCapture(redactor: redactor, maxSize: config.maxBodySize);
  }

  /// The active configuration.
  final NetworkLoggerConfig config;

  /// The redactor built from [config].
  final LogRedactor redactor;

  final RecordNetworkLog _record;
  late final BodyCapture _bodies;
  int _sequence = 0;

  /// Whether a call to [url] should be recorded.
  bool shouldLog(Uri url) => config.isEnabled && !config.isExcluded(url);

  /// A new identifier, unique within this capture policy.
  String nextId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${(_sequence++).toRadixString(36)}';

  /// The redacted [url].
  Uri url(Uri url) => redactor.redactUrl(url);

  /// Redacted headers, or an empty map when header capture is disabled.
  Map<String, String> headers(Map<String, String> headers) =>
      config.captureHeaders ? redactor.redactHeaders(headers) : const {};

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
