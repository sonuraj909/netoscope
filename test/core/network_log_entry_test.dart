import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import '../support/fixtures.dart';

void main() {
  group('NetworkLogEntry', () {
    test('copies header maps and exposes them as unmodifiable', () {
      final headers = {'accept': 'application/json'};
      final entry = makeEntry(requestHeaders: headers);
      headers['accept'] = 'text/plain';

      expect(entry.requestHeaders['accept'], 'application/json');
      expect(() => entry.requestHeaders['x'] = 'y', throwsUnsupportedError);
      expect(() => entry.responseHeaders['x'] = 'y', throwsUnsupportedError);
    });

    test('normalizes the method to upper case', () {
      expect(makeEntry(method: 'post').method, 'POST');
    });

    test('derives query parameters from the URL', () {
      final entry = makeEntry(url: 'https://x.dev/search?q=dart&tag=a&tag=b');
      expect(entry.queryParameters, {
        'q': ['dart'],
        'tag': ['a', 'b'],
      });
    });

    group('outcome', () {
      test('successful response', () {
        final entry = makeEntry(statusCode: 204);
        expect(entry.outcome, NetworkLogOutcome.success);
        expect(entry.isSuccess, isTrue);
        expect(entry.hasResponse, isTrue);
      });

      test('HTTP error response, with or without a client error', () {
        expect(makeEntry(statusCode: 404).outcome, NetworkLogOutcome.httpError);
        final rejected = makeEntry(
          statusCode: 500,
          error: const NetworkLogError(
            type: NetworkErrorType.badResponse,
            message: 'bad response',
          ),
        );
        expect(rejected.outcome, NetworkLogOutcome.httpError);
      });

      test('transport failure without a response', () {
        final entry = makeEntry(
          statusCode: null,
          error: const NetworkLogError(
            type: NetworkErrorType.timeout,
            message: 'receive timeout',
          ),
        );
        expect(entry.outcome, NetworkLogOutcome.failure);
        expect(entry.hasResponse, isFalse);
      });

      test('no response and no error is still a failure', () {
        expect(
          makeEntry(statusCode: null).outcome,
          NetworkLogOutcome.failure,
        );
      });

      test('cancellation wins over everything else', () {
        final entry = makeEntry(
          statusCode: null,
          error: const NetworkLogError(
            type: NetworkErrorType.cancelled,
            message: 'cancelled',
          ),
        );
        expect(entry.outcome, NetworkLogOutcome.cancelled);
      });
    });

    test('isSlower compares against the threshold inclusively', () {
      final entry = makeEntry(duration: const Duration(seconds: 2));
      expect(entry.isSlower(const Duration(seconds: 2)), isTrue);
      expect(entry.isSlower(const Duration(seconds: 3)), isFalse);
      expect(makeEntry(duration: null).isSlower(Duration.zero), isFalse);
    });

    test('toJson includes every captured field', () {
      final json = makeEntry(
        statusCode: 201,
        responseBody: const NetworkLogBody(
          kind: NetworkBodyKind.json,
          content: '{"id":1}',
        ),
      ).toJson();

      expect(json['method'], 'GET');
      expect(json['statusCode'], 201);
      expect(json['outcome'], 'success');
      expect(json['durationMs'], 120);
      expect(json['timestamp'], '2026-01-01T12:00:00.000Z');
      expect(json['responseBody'], {
        'kind': 'json',
        'format': 'json',
        'contentType': null,
        'content': '{"id":1}',
        'truncated': false,
      });
      expect(json['protocol'], 'http');
      expect(json['kind'], 'exchange');
      expect(json['details'], isEmpty);
      expect(json['error'], isNull);
    });
  });
}
