import '../../core/entities/network_log_error.dart';
import '../../core/entities/webhook_details.dart';
import 'webhook_config.dart';

/// Classifies outbound webhook delivery attempts.
class WebhookInspector {
  /// Creates an inspector.
  const WebhookInspector(this.config);

  /// The webhook configuration.
  final WebhookConfig config;

  /// Header names (lower-case) whose values must always be redacted.
  Set<String> get signatureHeaders =>
      {for (final name in config.signatureHeaders) name.toLowerCase()};

  /// Describes an attempt, or returns `null` if the request is not a
  /// webhook delivery.
  ///
  /// [requestHeaders] are the raw headers; only the signature algorithm
  /// prefix is read from signature headers.
  WebhookDetails? inspect({
    required Uri url,
    required Map<String, String> requestHeaders,
    WebhookAttempt? attempt,
    int? statusCode,
    NetworkLogError? error,
  }) {
    if (attempt == null && !config.matches(url)) return null;
    final headers = {
      for (final e in requestHeaders.entries) e.key.toLowerCase(): e.value,
    };
    String? header(List<String> names) {
      for (final name in names) {
        final value = headers[name.toLowerCase()];
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final number =
        attempt?.attempt ?? int.tryParse(header(config.attemptHeaders) ?? '');
    final maxAttempts = attempt?.maxAttempts ?? config.maxAttempts;
    return WebhookDetails(
      outcome: classify(
        statusCode: statusCode,
        error: error,
        attempt: number,
        maxAttempts: maxAttempts,
      ),
      eventType: attempt?.eventType ?? header(config.eventTypeHeaders),
      deliveryId: attempt?.deliveryId ?? header(config.deliveryIdHeaders),
      attempt: number,
      maxAttempts: maxAttempts,
      signatureAlgorithm: signatureAlgorithm(header(config.signatureHeaders)),
      deliveryError: error?.message ??
          (statusCode != null && statusCode >= 300 ? 'HTTP $statusCode' : null),
    );
  }

  /// The outcome of an attempt.
  static WebhookOutcome classify({
    int? statusCode,
    NetworkLogError? error,
    int? attempt,
    int? maxAttempts,
  }) {
    if (error?.type == NetworkErrorType.cancelled) {
      return WebhookOutcome.unknown;
    }
    final code = statusCode;
    if (code != null && code >= 200 && code < 300) {
      return WebhookOutcome.delivered;
    }
    final retryable = code == null
        ? error != null
        : code == 408 || code == 425 || code == 429 || code >= 500;
    if (!retryable) {
      return code == null ? WebhookOutcome.unknown : WebhookOutcome.rejected;
    }
    final isLast =
        attempt != null && maxAttempts != null && attempt >= maxAttempts;
    return isLast ? WebhookOutcome.exhausted : WebhookOutcome.retryable;
  }

  static final RegExp _algorithm = RegExp(
    r'^\s*(sha-?\d{1,3}|hmac[\w\-]{0,12}|v\d{1,2}|ed25519|rsa[\w\-]{0,12}|md5)'
    r'\s*[=,]',
    caseSensitive: false,
  );

  /// The algorithm prefix of a signature header value (`sha256=…` →
  /// `sha256`, `t=…,v1=…` → `v1`, `v1,…` → `v1`), or `present` when none is
  /// recognizable. Only known algorithm names can be returned, so the
  /// signature itself never is.
  static String? signatureAlgorithm(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(',');
    for (final part in parts) {
      final match = _algorithm.firstMatch('$part,');
      final name = match?.group(1);
      if (name != null) return name.toLowerCase();
    }
    return 'present';
  }
}
