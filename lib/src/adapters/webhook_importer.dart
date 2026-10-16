import '../core/entities/network_event_kind.dart';
import '../core/entities/network_log_entry.dart';
import '../core/entities/network_log_error.dart';
import '../core/entities/webhook_details.dart';
import '../protocols/webhook/webhook_delivery_record.dart';
import '../protocols/webhook/webhook_inspector.dart';
import 'log_capture.dart';

/// Converts backend webhook delivery logs into redacted entries.
class WebhookImporter {
  /// Creates an importer recording through [capture].
  const WebhookImporter(this._capture);

  final LogCapture _capture;

  /// Records each of [records] as an exchange with [WebhookDetails] whose
  /// source is [WebhookSource.imported]. Excluded endpoints are skipped.
  void import(Iterable<WebhookDeliveryRecord> records) {
    for (final record in records) {
      _capture.record(() => _entry(record));
    }
  }

  NetworkLogEntry? _entry(WebhookDeliveryRecord record) {
    if (!_capture.shouldLog(record.endpoint)) return null;
    final message = record.error;
    final error = message == null
        ? null
        : _capture.error(NetworkErrorType.unknown, message);
    final inspector = WebhookInspector(_capture.config.webhooks);
    final headers = {
      for (final e in record.requestHeaders.entries)
        e.key.toLowerCase(): e.value,
    };
    String? signature;
    for (final name in inspector.signatureHeaders) {
      signature ??= headers[name];
    }
    final details = WebhookDetails(
      source: WebhookSource.imported,
      outcome: record.outcome ??
          WebhookInspector.classify(
            statusCode: record.statusCode,
            error: error,
            attempt: record.attempt,
            maxAttempts: record.maxAttempts,
          ),
      eventType: record.eventType,
      deliveryId: record.deliveryId,
      attempt: record.attempt,
      maxAttempts: record.maxAttempts,
      signatureAlgorithm: WebhookInspector.signatureAlgorithm(signature),
      deliveryError: error?.message ??
          (record.statusCode != null && record.statusCode! >= 300
              ? 'HTTP ${record.statusCode}'
              : null),
    );
    final url = record.endpoint;
    return NetworkLogEntry(
      id: _capture.nextId(),
      method: record.method,
      url: _capture.url(url),
      timestamp: record.timestamp,
      duration: record.duration,
      statusCode: record.statusCode,
      error: error,
      requestHeaders: _capture.headers(record.requestHeaders),
      requestBody: _capture.requestBody(
        (b) => b.capture(
          record.requestBody,
          context: _capture.payload(
            url,
            MessageDirection.outgoing,
            contentType: headers['content-type'],
          ),
        ),
      ),
      responseBody: _capture.responseBody(
        (b) => b.capture(
          record.responseBody,
          context: _capture.payload(url, MessageDirection.incoming),
        ),
      ),
      details: [details],
      metadata: const {'source': 'imported'},
    );
  }
}
