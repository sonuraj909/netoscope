import '../../core/entities/webhook_details.dart';

/// A webhook delivery attempt reported by a backend, for import with
/// `Netoscope.importWebhookDeliveries`.
///
/// A Flutter app cannot observe server-to-server webhook traffic. If your
/// backend keeps delivery logs, fetch them through your own API and convert
/// each attempt into a record. Values are redacted on import like any other
/// captured data.
class WebhookDeliveryRecord {
  /// Creates a record.
  const WebhookDeliveryRecord({
    required this.endpoint,
    required this.timestamp,
    this.method = 'POST',
    this.eventType,
    this.deliveryId,
    this.attempt,
    this.maxAttempts,
    this.statusCode,
    this.duration,
    this.error,
    this.outcome,
    this.requestHeaders = const {},
    this.requestBody,
    this.responseBody,
  });

  /// The receiver URL.
  final Uri endpoint;

  /// When the attempt started.
  final DateTime timestamp;

  /// The HTTP method, usually `POST`.
  final String method;

  /// The event type, such as `invoice.paid`.
  final String? eventType;

  /// The delivery identifier.
  final String? deliveryId;

  /// The attempt number, starting at 1.
  final int? attempt;

  /// The maximum number of attempts.
  final int? maxAttempts;

  /// The receiver's HTTP status, if a response was received.
  final int? statusCode;

  /// How long the attempt took.
  final Duration? duration;

  /// A description of a transport failure, if any.
  final String? error;

  /// The outcome reported by the backend. Derived from [statusCode],
  /// [error] and the attempt counts when omitted.
  final WebhookOutcome? outcome;

  /// The request headers sent. Signature headers are reduced to their
  /// algorithm.
  final Map<String, String> requestHeaders;

  /// The payload sent (string, bytes, map or list).
  final Object? requestBody;

  /// The receiver's response body.
  final Object? responseBody;
}
