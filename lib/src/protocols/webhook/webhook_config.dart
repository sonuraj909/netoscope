/// Explicit webhook information for one outbound delivery attempt.
///
/// With Dio, attach it to the request:
/// `Options(extra: {Netoscope.webhookKey: WebhookAttempt(...)})`.
class WebhookAttempt {
  /// Creates attempt information.
  const WebhookAttempt({
    this.eventType,
    this.deliveryId,
    this.attempt,
    this.maxAttempts,
  });

  /// The event type, such as `order.created`.
  final String? eventType;

  /// The delivery identifier.
  final String? deliveryId;

  /// The attempt number, starting at 1.
  final int? attempt;

  /// The maximum number of attempts the sender will make.
  final int? maxAttempts;
}

/// How outbound webhook deliveries are recognized and described.
///
/// A request is treated as a webhook delivery when its URL matches
/// [endpoints], or (with Dio) when it carries a [WebhookAttempt]. Header
/// names are matched case-insensitively.
class WebhookConfig {
  /// Creates a webhook configuration.
  const WebhookConfig({
    this.endpoints = const [],
    this.maxAttempts,
    this.deliveryIdHeaders = const [
      'webhook-id',
      'x-webhook-id',
      'x-delivery-id',
      'x-github-delivery',
    ],
    this.eventTypeHeaders = const [
      'x-webhook-event',
      'webhook-event',
      'x-event-type',
      'x-github-event',
    ],
    this.attemptHeaders = const ['x-webhook-attempt', 'webhook-attempt'],
    this.signatureHeaders = const [
      'webhook-signature',
      'x-webhook-signature',
      'x-signature',
      'x-hub-signature',
      'x-hub-signature-256',
      'stripe-signature',
    ],
  });

  /// URL patterns (substring [String]s or [RegExp]s) of webhook receivers.
  final List<Pattern> endpoints;

  /// The default maximum number of attempts, used to detect exhaustion.
  final int? maxAttempts;

  /// Headers that carry the delivery identifier.
  final List<String> deliveryIdHeaders;

  /// Headers that carry the event type.
  final List<String> eventTypeHeaders;

  /// Headers that carry the attempt number.
  final List<String> attemptHeaders;

  /// Headers that carry a signature. Their values are always fully redacted;
  /// only the algorithm prefix is reported.
  final List<String> signatureHeaders;

  /// Whether [url] is a configured webhook endpoint.
  bool matches(Uri url) {
    if (endpoints.isEmpty) return false;
    final text = url.toString();
    return endpoints.any(text.contains);
  }
}
