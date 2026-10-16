import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

void main() {
  late Netoscope netoscope;
  final url = Uri.parse('wss://rt.example.com/socket?token=secret');

  setUp(() {
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
  });
  tearDown(() => netoscope.dispose());

  List<NetworkLogEntry> oldestFirst() => netoscope.logs.reversed.toList();

  group('WebSocketRecorder', () {
    test('records lifecycle and both directions without altering data',
        () async {
      final incoming = StreamController<Object>();
      final outgoing = StreamController<Object>();
      final socket = netoscope.webSocket(url)..connected(subprotocol: 'chat');

      final stream = socket.observeIncoming(
        incoming.stream,
        closeCode: () => 1000,
        closeReason: () => 'bye',
      );
      final sink = socket.observeOutgoing(outgoing.sink);
      final sentOnWire = <Object>[];
      outgoing.stream.listen(sentOnWire.add);
      final seen = <Object>[];
      final done = stream.listen(seen.add).asFuture<void>();

      sink.add('{"password":"p1","text":"hi"}');
      incoming
        ..add('{"text":"hello"}')
        ..add([1, 2, 3]);
      await incoming.close();
      await done;

      expect(seen, [
        '{"text":"hello"}',
        [1, 2, 3]
      ]);
      expect(sentOnWire, ['{"password":"p1","text":"hi"}']);

      final logs = oldestFirst();
      expect(logs.map((e) => (e.kind, e.direction, e.lifecycle)), [
        (NetworkEventKind.connection, null, ConnectionLifecycle.opened),
        (NetworkEventKind.message, MessageDirection.outgoing, null),
        (NetworkEventKind.message, MessageDirection.incoming, null),
        (NetworkEventKind.message, MessageDirection.incoming, null),
        (NetworkEventKind.connection, null, ConnectionLifecycle.closed),
      ]);
      expect(
          logs.every((e) => e.connectionId == logs.first.connectionId), isTrue);
      expect(logs.first.url.queryParameters['token'], '***');
      expect(logs[1].requestBody!.content, '{"password":"***","text":"hi"}');
      expect(
        logs[3].detail<WebSocketDetails>()!.frameType,
        WebSocketFrameType.binary,
      );
      final close = logs.last.detail<WebSocketDetails>()!;
      expect(close.closeCode, 1000);
      expect(close.closeReason, 'bye');
      expect(
          logs.last.metadata, {'messagesSent': '1', 'messagesReceived': '2'});
    });

    test('forwards backpressure and cancellation to the source', () async {
      var paused = false;
      var cancelled = false;
      final source = StreamController<String>(
        onPause: () => paused = true,
        onResume: () => paused = false,
        onCancel: () => cancelled = true,
      );
      final socket = netoscope.webSocket(url);
      final subscription = socket.observeIncoming(source.stream).listen(null);

      subscription.pause();
      expect(paused, isTrue);
      subscription.resume();
      expect(paused, isFalse);
      await subscription.cancel();

      expect(cancelled, isTrue);
      expect(netoscope.logs.single.metadata['closedBy'], 'client');
    });

    test('errors reach the app and are recorded once as a failure', () async {
      final socket = netoscope.webSocket(url);
      final stream = socket.observeIncoming(
        Stream<String>.error(StateError('connection reset')),
      );

      await expectLater(stream.toList(), throwsStateError);

      expect(netoscope.logs, hasLength(1));
      expect(netoscope.logs.single.lifecycle, ConnectionLifecycle.failed);
      expect(netoscope.logs.single.outcome, NetworkLogOutcome.failure);
    });

    test('broadcast streams are returned as-is and recorded once', () async {
      final source = StreamController<String>.broadcast();
      final stream = source.stream;
      final socket = netoscope.webSocket(url);
      final observed = socket.observeIncoming(stream);

      expect(identical(observed, stream), isTrue);
      final a = <String>[];
      final b = <String>[];
      observed
        ..listen(a.add)
        ..listen(b.add);
      source.add('x');
      await pumpEventQueue();

      expect(a, ['x']);
      expect(b, ['x']);
      expect(netoscope.logs, hasLength(1));
      await source.close();
    });

    test('ignored messages are counted but not recorded', () async {
      final socket = netoscope.webSocket(
        url,
        ignoreMessage: (message) => message == 'ping',
      );
      socket
        ..received('ping')
        ..received('data')
        ..disconnected();

      expect(netoscope.logs, hasLength(2));
      expect(netoscope.logs.first.metadata['messagesReceived'], '2');
    });

    test('message capture can be turned off', () {
      netoscope = Netoscope(
        config: const NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
          captureRealtimeMessages: false,
        ),
      );
      netoscope.webSocket(url)
        ..connected()
        ..sent('a')
        ..disconnected();

      expect(netoscope.logs.map((e) => e.kind),
          everyElement(NetworkEventKind.connection));
    });

    test('recognizes graphql-transport-ws operations and errors', () {
      netoscope.webSocket(url)
        ..sent(
          jsonEncode({
            'id': '1',
            'type': 'subscribe',
            'payload': {'query': 'subscription OnPrice { price }'},
          }),
        )
        ..received(
          jsonEncode({
            'id': '1',
            'type': 'next',
            'payload': {
              'errors': [
                {'message': 'denied'},
              ],
            },
          }),
        );

      final logs = oldestFirst();
      expect(
        logs.first.graphQL!.operations.single.type,
        GraphQLOperationType.subscription,
      );
      expect(logs.last.hasGraphQLErrors, isTrue);
    });

    test('is inert when logging is disabled', () {
      final disabled =
          Netoscope(config: const NetworkLoggerConfig(enabled: false));
      final source = StreamController<String>();
      final socket = disabled.webSocket(url);

      expect(socket.isActive, isFalse);
      final stream = source.stream;
      expect(identical(socket.observeIncoming(stream), stream), isTrue);
      final sink = source.sink;
      expect(identical(socket.observeOutgoing(sink), sink), isTrue);
      socket.received('x');
      expect(disabled.logs, isEmpty);
      source.close();
    });
  });

  test('SseRecorder parses raw bytes from any client', () async {
    final sse = netoscope.serverSentEvents(Uri.parse('https://rt.dev/feed'))
      ..connected(statusCode: 200);
    final bytes = sse.observeBytes(
      Stream.fromIterable([
        utf8.encode('event: tick\nid: 1\ndata: 1\n\n'),
        utf8.encode('data: 2\n\n'),
      ]),
    );

    expect(await bytes.length, 2, reason: 'chunks pass through');
    final events =
        oldestFirst().where((e) => e.kind == NetworkEventKind.message);
    expect(events.map((e) => e.detail<SseDetails>()!.eventType),
        ['tick', 'message']);
    expect(netoscope.logs.first.metadata['closedBy'], 'server');
  });

  test('MqttRecorder records the session', () {
    netoscope.mqtt(Uri.parse('mqtts://broker.dev'), clientId: 'app-1')
      ..connected()
      ..subscribed('devices/+/state', qos: 1)
      ..published('devices/1/cmd', '{"on":true}', qos: 1)
      ..received('devices/1/state', utf8.encode('{"on":true}'), retained: true)
      ..disconnected();

    final logs = oldestFirst();
    expect(logs, hasLength(5));
    expect(logs.every((e) => e.protocol == NetworkProtocol.mqtt), isTrue);
    expect(logs[1].metadata['packet'], 'SUBSCRIBE');
    expect(logs[2].detail<MqttDetails>()!.topic, 'devices/1/cmd');
    expect(logs[3].detail<MqttDetails>()!.retained, isTrue);
    expect(logs[3].responseBody!.content, '{"on":true}');
  });

  group('GrpcCallRecorder', () {
    test('records a unary call as one exchange', () {
      netoscope.grpcCall(
        '/helloworld.Greeter/SayHello',
        host: Uri.parse('https://grpc.dev'),
        metadata: {'authorization': 'Bearer t'},
      )
        ..sent({'name': 'Ada'})
        ..received({'message': 'Hello Ada'})
        ..finish();

      final entry = netoscope.logs.single;
      final grpc = entry.detail<GrpcDetails>()!;
      expect(entry.protocol, NetworkProtocol.grpc);
      expect(entry.kind, NetworkEventKind.exchange);
      expect(entry.outcome, NetworkLogOutcome.success);
      expect(entry.requestHeaders['authorization'], '***');
      expect(entry.requestBody!.content, '{"name":"Ada"}');
      expect(grpc.service, 'helloworld.Greeter');
      expect(grpc.statusName, 'OK');
      expect(grpc.messagesSent, 1);
    });

    test('records streaming messages and error statuses', () {
      netoscope.grpcCall(
        '/chat.Chat/Stream',
        callType: GrpcCallType.bidiStreaming,
        encodeMessage: (m) => {'text': '$m'},
      )
        ..sent('a')
        ..received('b')
        ..received('c')
        ..finish(statusCode: 14, statusMessage: 'unavailable');

      final logs = oldestFirst();
      expect(logs, hasLength(4));
      expect(logs[2].responseBody!.content, '{"text":"c"}');
      final call = logs.last;
      expect(call.outcome, NetworkLogOutcome.failure);
      expect(call.error!.type, NetworkErrorType.connection);
      expect(call.detail<GrpcDetails>()!.messagesReceived, 2);
    });
  });

  test('ConnectionRecorder supports custom protocols', () {
    netoscope.connection(Uri.parse('tcp://printer.local:9100'), label: 'RAW')
      ..opened()
      ..message(MessageDirection.outgoing, 'PRINT')
      ..failed(TimeoutException('no reply'));

    final logs = oldestFirst();
    expect(logs.first.protocol, NetworkProtocol.other);
    expect(logs.first.method, 'RAW');
    expect(logs.last.error!.type, NetworkErrorType.timeout);
  });

  test('importWebhookDeliveries redacts backend records', () {
    netoscope.importWebhookDeliveries([
      WebhookDeliveryRecord(
        endpoint: Uri.parse('https://receiver.dev/hook'),
        timestamp: DateTime.utc(2026, 5, 1),
        eventType: 'invoice.paid',
        attempt: 1,
        statusCode: 500,
        duration: const Duration(milliseconds: 80),
        requestHeaders: const {
          'Stripe-Signature': 't=1,v1=abcdef',
          'Content-Type': 'application/json',
        },
        requestBody: const {'invoice': 'in_1', 'client_secret': 'cs_x'},
      ),
    ]);

    final entry = netoscope.logs.single;
    final webhook = entry.webhook!;
    expect(webhook.source, WebhookSource.imported);
    expect(webhook.outcome, WebhookOutcome.retryable);
    expect(webhook.signatureAlgorithm, 'v1');
    expect(entry.requestHeaders['Stripe-Signature'], '***');
    expect(
        entry.requestBody!.content, '{"invoice":"in_1","client_secret":"***"}');
    expect(entry.timestamp, DateTime.utc(2026, 5, 1));
    expect(netoscope.exportJson(), isNot(contains('abcdef')));
  });
}
