import 'protocol_details.dart';

/// Where webhook delivery information came from.
enum WebhookSource {
  /// An outbound delivery made by an instrumented client in this app.
  outbound,

  /// A delivery record imported from a backend log.
  imported,
}

/// The result of one delivery attempt.
enum WebhookOutcome {
  /// The receiver accepted the delivery (2xx).
  delivered,

  /// Failed in a way that is normally retried (timeouts, 408, 429, 5xx).
  retryable,

  /// Failed retryably on the last allowed attempt.
  exhausted,

  /// Rejected in a way that is normally not retried (other 4xx).
  rejected,

  /// Not known (for example, an imported record without a result).
  unknown,
}

/// Webhook delivery attempt information.
///
/// Signature headers are never stored in full: only the algorithm prefix
/// (for example `sha256`) is kept.
class WebhookDetails extends ProtocolDetails {
  /// Creates webhook details.
  const WebhookDetails({
    required this.outcome,
    this.source = WebhookSource.outbound,
    this.eventType,
    this.deliveryId,
    this.attempt,
    this.maxAttempts,
    this.signatureAlgorithm,
    this.deliveryError,
  });

  /// The result of this attempt.
  final WebhookOutcome outcome;

  /// Where the information came from.
  final WebhookSource source;

  /// The event type, such as `order.created`.
  final String? eventType;

  /// The delivery identifier.
  final String? deliveryId;

  /// The attempt number, starting at 1.
  final int? attempt;

  /// The maximum number of attempts, when known.
  final int? maxAttempts;

  /// The signature algorithm, such as `sha256`, when a signature was sent.
  final String? signatureAlgorithm;

  /// A (redacted) description of why delivery failed.
  final String? deliveryError;

  @override
  String get type => 'webhook';

  @override
  String get label => 'Webhook';

  @override
  Map<String, String> describe() => {
        'Outcome': outcome.name,
        'Source': source.name,
        if (eventType != null) 'Event': eventType!,
        if (deliveryId != null) 'Delivery ID': deliveryId!,
        if (attempt != null)
          'Attempt':
              maxAttempts == null ? '$attempt' : '$attempt of $maxAttempts',
        if (signatureAlgorithm != null)
          'Signature': '$signatureAlgorithm (value hidden)',
        if (deliveryError != null) 'Delivery error': deliveryError!,
      };

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'outcome': outcome.name,
        'source': source.name,
        'eventType': eventType,
        'deliveryId': deliveryId,
        'attempt': attempt,
        'maxAttempts': maxAttempts,
        'signatureAlgorithm': signatureAlgorithm,
        'deliveryError': deliveryError,
      };
}
