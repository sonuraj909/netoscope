@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

NetworkLogEntry _rich() => NetworkLogEntry(
      id: 'rich',
      method: 'POST',
      url: Uri.parse('https://api.dev/graphql?api_key=***&page=2'),
      timestamp: DateTime.utc(2026, 3, 4, 5, 6, 7, 890),
      statusCode: 200,
      duration: const Duration(milliseconds: 243),
      requestSize: 52,
      responseSize: 164,
      requestHeaders: const {
        'content-type': 'application/json',
        'Authorization': '***'
      },
      responseHeaders: const {'content-type': 'application/json'},
      requestBody: const NetworkLogBody(
        kind: NetworkBodyKind.json,
        content: '{"query":"query Me { me { id } }"}',
        contentType: 'application/json',
      ),
      responseBody: const NetworkLogBody(
        kind: NetworkBodyKind.binary,
        content: '<protobuf, 3 bytes>',
        format: PayloadFormat.protobuf,
        isTruncated: true,
      ),
      error: const NetworkLogError(
          type: NetworkErrorType.timeout, message: 'slow'),
      protocol: NetworkProtocol.grpc,
      connectionId: 'c1',
      tags: const ['login-flow'],
      metadata: const {'source': 'ios'},
      details: [
        GraphQLDetails(
          operations: const [
            GraphQLOperation(
                name: 'Me', type: GraphQLOperationType.query, variables: '{}'),
          ],
          errors: [
            GraphQLError(
                message: 'x',
                path: const ['me', 0],
                code: 'E',
                operationIndex: 0)
          ],
          hasData: true,
        ),
        const WebhookDetails(
            outcome: WebhookOutcome.retryable, attempt: 2, maxAttempts: 3),
        const GrpcDetails(
            service: 's', method: 'm', statusCode: 5, isWeb: true),
        const SseDetails(
            eventType: 'tick', eventId: '7', retry: Duration(seconds: 2)),
        const WebSocketDetails(
            frameType: WebSocketFrameType.text, closeCode: 1000),
        const MqttDetails(topic: 't', qos: 1, retained: true),
        const TransferDetails(
            direction: TransferDirection.upload,
            bytesTransferred: 10,
            totalBytes: 20),
      ],
    );

void main() {
  test('entries survive a JSON round trip', () {
    final original = _rich();
    final restored = NetworkLogEntry.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
    );
    expect(jsonEncode(restored.toJson()), jsonEncode(original.toJson()));
    expect(restored.detail<SseDetails>()!.retry, const Duration(seconds: 2));
    expect(restored.responseBody!.format, PayloadFormat.protobuf);
    expect(restored.graphQL!.errors.single.path, ['me', 0]);
  });

  test('decoding tolerates missing and unknown fields', () {
    final entry = NetworkLogEntry.fromJson({
      'id': 'x',
      'url': 'https://a.dev',
      'kind': 'somethingNew',
      'details': [
        {'type': 'custom'},
        'garbage',
      ],
    });
    expect(entry.method, 'GET');
    expect(entry.kind, NetworkEventKind.exchange);
    expect(entry.details, isEmpty);
  });

  group('PersistentNetworkLogStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('netoscope'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('history survives a restart, newest first', () async {
      final path = '${dir.path}/logs/history.json';
      final first = await PersistentNetworkLogStore.open(
        FileNetworkLogPersistence(path),
        saveDelay: const Duration(milliseconds: 10),
      );
      final netoscope = Netoscope(
        store: first,
        config:
            const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
      );
      first
        ..add(_rich())
        ..add(NetworkLogEntry(
          id: 'newer',
          method: 'GET',
          url: Uri.parse('https://api.dev/users'),
          timestamp: DateTime.utc(2026),
          statusCode: 200,
        ));
      expect(netoscope.logs, hasLength(2));
      await first.dispose();
      expect(File(path).existsSync(), isTrue);

      final second = await PersistentNetworkLogStore.open(
        FileNetworkLogPersistence(path),
      );
      expect(second.entries.map((e) => e.id), ['newer', 'rich']);
      expect(second.entries.last.tags, ['login-flow']);
      second.clear();
      await second.dispose();

      final third = await PersistentNetworkLogStore.open(
        FileNetworkLogPersistence(path),
      );
      expect(third.entries, isEmpty, reason: 'clearing is persisted');
      await third.dispose();
    });

    test('respects maxEntries and survives corrupt files', () async {
      final path = '${dir.path}/history.json';
      File(path).writeAsStringSync('{not json');
      final store = await PersistentNetworkLogStore.open(
        FileNetworkLogPersistence(path),
        maxEntries: 2,
      );
      expect(store.entries, isEmpty);
      for (var i = 0; i < 5; i++) {
        store.add(NetworkLogEntry(
          id: '$i',
          method: 'GET',
          url: Uri.parse('https://a.dev/$i'),
          timestamp: DateTime.utc(2026),
        ));
      }
      await store.dispose();
      final reopened = await PersistentNetworkLogStore.open(
        FileNetworkLogPersistence(path),
        maxEntries: 2,
      );
      expect(reopened.entries.map((e) => e.id), ['4', '3']);
      await reopened.dispose();
    });
  });

  group('HAR export', () {
    test('produces HAR 1.2 with requests, responses and timings', () {
      final netoscope = Netoscope(
        store: InMemoryNetworkLogStore()
          ..add(_rich())
          ..add(NetworkLogEntry(
            id: 'ws',
            method: 'WS',
            url: Uri.parse('wss://rt.dev'),
            timestamp: DateTime.utc(2026),
            kind: NetworkEventKind.message,
          ))
          ..add(NetworkLogEntry(
            id: 'later',
            method: 'GET',
            url: Uri.parse('https://api.dev/users'),
            timestamp: DateTime.utc(2026, 5),
            statusCode: 200,
            duration: const Duration(milliseconds: 90),
            responseBody: const NetworkLogBody(
              kind: NetworkBodyKind.json,
              content: '[]',
            ),
          )),
        config:
            const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
      );

      final har = jsonDecode(netoscope.exportHar()) as Map<String, Object?>;
      final log = har['log']! as Map<String, Object?>;
      expect(log['version'], '1.2');
      final entries = (log['entries']! as List).cast<Map<String, Object?>>();
      expect(entries, hasLength(2), reason: 'WebSocket messages are skipped');

      final first = entries.first;
      expect(first['startedDateTime'], '2026-03-04T05:06:07.890Z');
      expect(first['time'], 243);
      final request = first['request']! as Map<String, Object?>;
      expect(request['method'], 'POST');
      expect(request['queryString'], [
        {'name': 'api_key', 'value': '***'},
        {'name': 'page', 'value': '2'},
      ]);
      expect((request['postData']! as Map)['mimeType'], 'application/json');
      final response = first['response']! as Map<String, Object?>;
      expect(response['status'], 200);
      expect((response['content']! as Map).containsKey('text'), isFalse);
      expect(first['comment'], contains('Response body: <protobuf, 3 bytes>'));
      expect(first['_tags'], ['login-flow']);

      final second = entries.last;
      expect(((second['response']! as Map)['content']! as Map)['text'], '[]');
    });
  });
}
