import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netoscope/netoscope.dart';

List<int> _frame(List<int> data, {int flag = 0}) => [
      flag,
      (data.length >> 24) & 0xff,
      (data.length >> 16) & 0xff,
      (data.length >> 8) & 0xff,
      data.length & 0xff,
      ...data,
    ];

void main() {
  late Netoscope netoscope;

  setUp(() {
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        webhooks:
            WebhookConfig(endpoints: ['hooks.partner.dev'], maxAttempts: 3),
      ),
    );
  });
  tearDown(() => netoscope.dispose());

  group('GraphQL over package:http', () {
    test('a 200 with errors is a transport success with GraphQL errors',
        () async {
      final client = netoscope.httpClient(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {'viewer': null},
              'errors': [
                {
                  'message': 'Unauthenticated',
                  'path': ['viewer']
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );

      final response = await client.post(
        Uri.parse('https://api.dev/graphql'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'query': 'query Viewer { viewer { id } }'}),
      );

      expect(response.statusCode, 200);
      final entry = netoscope.logs.single;
      expect(entry.outcome, NetworkLogOutcome.success);
      expect(entry.hasGraphQLErrors, isTrue);
      expect(entry.graphQL!.operations.single.name, 'Viewer');
      expect(entry.graphQL!.errors.single.pathLabel, 'viewer');
    });

    test('still parses GraphQL when response body capture is off', () async {
      netoscope = Netoscope(
        config: const NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
          captureResponseBody: false,
        ),
      );
      final client = netoscope.httpClient(
        MockClient(
          (_) async => http.Response('{"errors":[{"message":"x"}]}', 200),
        ),
      );

      await client.post(
        Uri.parse('https://api.dev/graphql'),
        body: jsonEncode({'query': '{ a }'}),
      );

      final entry = netoscope.logs.single;
      expect(entry.responseBody, isNull);
      expect(entry.graphQL!.errors, hasLength(1));
    });
  });

  group('Server-Sent Events over package:http', () {
    test('records open, each event as it is read, and close', () async {
      final source = StreamController<List<int>>();
      final client = netoscope.httpClient(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            source.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );

      final response = await client.send(
        http.Request('GET', Uri.parse('https://rt.dev/events?token=abc')),
      );
      expect(netoscope.logs.single.lifecycle, ConnectionLifecycle.opened);

      final received = <String>[];
      final done = response.stream
          .transform(utf8.decoder)
          .listen(received.add)
          .asFuture<void>();
      source.add(
          utf8.encode('event: price\ndata: {"symbol":"X","apiKey":"k"}\n\n'));
      await pumpEventQueue();
      expect(netoscope.logs, hasLength(2), reason: 'events are live');

      source.add(utf8.encode('data: plain\n\n'));
      await source.close();
      await done;

      final logs = netoscope.logs.reversed.toList();
      expect(logs.map((e) => e.kind), [
        NetworkEventKind.connection,
        NetworkEventKind.message,
        NetworkEventKind.message,
        NetworkEventKind.connection,
      ]);
      expect(logs.every((e) => e.protocol == NetworkProtocol.sse), isTrue);
      expect(logs.map((e) => e.connectionId).toSet(), hasLength(1));
      expect(logs.first.url.queryParameters['token'], '***');
      expect(logs[1].detail<SseDetails>()!.eventType, 'price');
      expect(logs[1].responseBody!.content, '{"symbol":"X","apiKey":"***"}');
      expect(logs.last.lifecycle, ConnectionLifecycle.closed);
      expect(logs.last.metadata['messagesReceived'], '2');
      expect(received.join(), contains('data: plain'),
          reason: 'bytes unchanged');
    });

    test('cancelling the stream records a client-side close', () async {
      final client = netoscope.httpClient(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(
            Stream.periodic(
              const Duration(milliseconds: 1),
              (_) => utf8.encode('data: tick\n\n'),
            ),
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );

      final response = await client.send(
        http.Request('GET', Uri.parse('https://rt.dev/ticks')),
      );
      await response.stream.take(2).drain<void>();

      final close = netoscope.logs.first;
      expect(close.lifecycle, ConnectionLifecycle.closed);
      expect(close.metadata['closedBy'], 'client');
    });
  });

  test('gRPC-Web status trailers become failures', () async {
    final client = netoscope.httpClient(
      MockClient(
        (_) async => http.Response.bytes(
          [
            ..._frame([1, 2, 3]),
            ..._frame(
              utf8.encode(
                  'grpc-status: 5\r\ngrpc-message: user%20not%20found\r\n'),
              flag: 0x80,
            ),
          ],
          200,
          headers: {'content-type': 'application/grpc-web+proto'},
        ),
      ),
    );

    await client.post(
      Uri.parse('https://api.dev/users.v1.Users/GetUser'),
      headers: {'content-type': 'application/grpc-web+proto'},
      body: _frame([8, 1]),
    );

    final entry = netoscope.logs.single;
    final grpc = entry.detail<GrpcDetails>()!;
    expect(entry.protocol, NetworkProtocol.grpc);
    expect(grpc.service, 'users.v1.Users');
    expect(grpc.method, 'GetUser');
    expect(grpc.statusName, 'NOT_FOUND');
    expect(grpc.statusMessage, 'user not found');
    expect(grpc.messagesSent, 1);
    expect(grpc.messagesReceived, 1);
    expect(grpc.isWeb, isTrue);
    expect(entry.outcome, NetworkLogOutcome.failure);
    expect(entry.error!.message, 'gRPC NOT_FOUND: user not found');
  });

  test('webhook deliveries never expose signatures', () async {
    final client = netoscope.httpClient(
      MockClient((_) async => http.Response('down', 503)),
    );

    await client.post(
      Uri.parse('https://hooks.partner.dev/orders'),
      headers: {
        'webhook-id': 'msg_9',
        'x-webhook-attempt': '3',
        'x-hub-signature-256': 'sha256=feedface',
        'authorization': 'Bearer partner-token',
      },
      body: '{"event":"order.created"}',
    );

    final entry = netoscope.logs.single;
    final webhook = entry.webhook!;
    expect(webhook.outcome, WebhookOutcome.exhausted);
    expect(webhook.signatureAlgorithm, 'sha256');
    expect(entry.requestHeaders['x-hub-signature-256'], '***');
    expect(entry.requestHeaders['authorization'], '***');
    expect(netoscope.exportJson(), isNot(contains('feedface')));
    expect(netoscope.exportJson(), isNot(contains('partner-token')));
  });
}
