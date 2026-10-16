import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/protocols/webhook/webhook_inspector.dart';

void main() {
  group('outcome classification', () {
    WebhookOutcome classify(
            {int? status, NetworkErrorType? error, int? attempt, int? max}) =>
        WebhookInspector.classify(
          statusCode: status,
          error:
              error == null ? null : NetworkLogError(type: error, message: 'x'),
          attempt: attempt,
          maxAttempts: max,
        );

    test('2xx is delivered', () {
      expect(classify(status: 204), WebhookOutcome.delivered);
    });

    test('server errors, throttling and transport failures are retryable', () {
      expect(classify(status: 503), WebhookOutcome.retryable);
      expect(classify(status: 429), WebhookOutcome.retryable);
      expect(classify(status: 408), WebhookOutcome.retryable);
      expect(
          classify(error: NetworkErrorType.timeout), WebhookOutcome.retryable);
    });

    test('the last retryable attempt is exhausted', () {
      expect(
          classify(status: 500, attempt: 5, max: 5), WebhookOutcome.exhausted);
      expect(
          classify(status: 500, attempt: 4, max: 5), WebhookOutcome.retryable);
    });

    test('other client errors are rejected; cancellation is unknown', () {
      expect(classify(status: 410), WebhookOutcome.rejected);
      expect(
          classify(error: NetworkErrorType.cancelled), WebhookOutcome.unknown);
    });
  });

  group('signature algorithm', () {
    test('extracts only known algorithm names', () {
      expect(WebhookInspector.signatureAlgorithm('sha256=abcdef'), 'sha256');
      expect(
          WebhookInspector.signatureAlgorithm('t=1700000000,v1=abcdef'), 'v1');
      expect(
          WebhookInspector.signatureAlgorithm(
              'v1,K5oZfzN95Z9UVu1EsfQmfVNQhnkZ2pj9o9NDN/H/pI4='),
          'v1');
    });

    test('never returns signature material', () {
      expect(WebhookInspector.signatureAlgorithm('deadbeef'), 'present');
      expect(WebhookInspector.signatureAlgorithm('deadbeef=cafe'), 'present');
      expect(WebhookInspector.signatureAlgorithm(''), isNull);
    });
  });

  test('reads attempt metadata from headers', () {
    const inspector = WebhookInspector(
      WebhookConfig(endpoints: ['hooks.example.com'], maxAttempts: 3),
    );
    final details = inspector.inspect(
      url: Uri.parse('https://hooks.example.com/orders'),
      requestHeaders: {
        'Webhook-Id': 'msg_1',
        'X-Webhook-Event': 'order.created',
        'X-Webhook-Attempt': '3',
        'X-Hub-Signature-256': 'sha256=0123456789',
      },
      statusCode: 502,
    )!;
    expect(details.deliveryId, 'msg_1');
    expect(details.eventType, 'order.created');
    expect(details.attempt, 3);
    expect(details.outcome, WebhookOutcome.exhausted);
    expect(details.signatureAlgorithm, 'sha256');
    expect(details.deliveryError, 'HTTP 502');
    expect(details.toJson().toString(), isNot(contains('0123456789')));
  });

  test('ignores requests that are not webhooks', () {
    const inspector = WebhookInspector(WebhookConfig());
    expect(
      inspector
          .inspect(url: Uri.parse('https://a.dev/x'), requestHeaders: const {}),
      isNull,
    );
  });
}
