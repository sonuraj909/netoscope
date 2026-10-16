import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

NetworkLogEntry _event({
  NetworkProtocol protocol = NetworkProtocol.webSocket,
  NetworkEventKind kind = NetworkEventKind.message,
  ConnectionLifecycle? lifecycle,
  NetworkLogError? error,
  int? statusCode,
  Duration? duration,
  List<ProtocolDetails> details = const [],
}) =>
    NetworkLogEntry(
      id: 'e',
      method: 'WS',
      url: Uri.parse('wss://rt.example.com/socket'),
      timestamp: DateTime.utc(2026),
      protocol: protocol,
      kind: kind,
      lifecycle: lifecycle,
      error: error,
      statusCode: statusCode,
      duration: duration,
      details: details,
    );

void main() {
  group('outcome for non-HTTP events', () {
    test('messages and lifecycle events without errors succeed', () {
      expect(_event().outcome, NetworkLogOutcome.success);
      expect(
        _event(
          kind: NetworkEventKind.connection,
          lifecycle: ConnectionLifecycle.closed,
        ).outcome,
        NetworkLogOutcome.success,
      );
    });

    test('failed connections and errors are failures', () {
      expect(
        _event(
          kind: NetworkEventKind.connection,
          lifecycle: ConnectionLifecycle.failed,
        ).outcome,
        NetworkLogOutcome.failure,
      );
      expect(
        _event(
          protocol: NetworkProtocol.grpc,
          kind: NetworkEventKind.exchange,
          error: const NetworkLogError(
            type: NetworkErrorType.unknown,
            message: 'NOT_FOUND',
          ),
        ).outcome,
        NetworkLogOutcome.failure,
      );
    });

    test('connection lifetimes are never slow', () {
      final closed = _event(
        kind: NetworkEventKind.connection,
        lifecycle: ConnectionLifecycle.closed,
        duration: const Duration(minutes: 5),
      );
      expect(closed.isSlower(const Duration(seconds: 1)), isFalse);
    });
  });

  test('details are typed, unmodifiable and exported', () {
    final graphQL = GraphQLDetails(
      operations: const [
        GraphQLOperation(name: 'GetUser', type: GraphQLOperationType.query),
      ],
      errors: [
        GraphQLError(message: 'denied', path: const ['user', 0, 'email']),
      ],
      hasData: true,
    );
    final entry = _event(
      protocol: NetworkProtocol.http,
      kind: NetworkEventKind.exchange,
      statusCode: 200,
      details: [graphQL, const SseDetails(eventType: 'tick')],
    );

    expect(entry.graphQL, same(graphQL));
    expect(entry.detail<SseDetails>()!.eventType, 'tick');
    expect(entry.webhook, isNull);
    expect(entry.hasGraphQLErrors, isTrue);
    expect(entry.outcome, NetworkLogOutcome.success);
    expect(graphQL.isPartial, isTrue);
    expect(graphQL.errors.single.pathLabel, 'user.0.email');
    expect(() => entry.details.add(graphQL), throwsUnsupportedError);

    final json = entry.toJson();
    final exported =
        (json['details']! as List<Object?>).cast<Map<String, Object?>>();
    expect(exported.map((d) => d['type']), ['graphql', 'sse']);
  });

  test('gRPC status names', () {
    expect(
      const GrpcDetails(service: 's', method: 'm', statusCode: 5).statusName,
      'NOT_FOUND',
    );
    expect(
      const GrpcDetails(service: 's', method: 'm', statusCode: 99).statusName,
      'UNKNOWN(99)',
    );
  });

  test('transfer progress', () {
    const partial = TransferDetails(
      direction: TransferDirection.download,
      bytesTransferred: 25,
      totalBytes: 100,
    );
    expect(partial.fraction, 0.25);
    expect(partial.isComplete, isFalse);
    expect(partial.describe()['Progress'], '25%');
  });

  test('payload formats are open and compare by id', () {
    const custom = PayloadFormat('msgpack', label: 'MessagePack');
    expect(custom, const PayloadFormat('msgpack', label: 'other label'));
    expect(
      const NetworkLogBody(kind: NetworkBodyKind.text, content: '').format,
      PayloadFormat.text,
    );
    expect(
      const NetworkLogBody(
        kind: NetworkBodyKind.text,
        content: '<a/>',
        format: PayloadFormat.xml,
      ).format,
      PayloadFormat.xml,
    );
  });
}
