import 'package:netoscope/netoscope.dart';

final DateTime fixtureNow = DateTime.utc(2026, 6, 1, 12);

/// A mixed history: HTTP, GraphQL, WebSocket, SSE, gRPC and MQTT.
List<NetworkLogEntry> protocolFixtures() {
  final ws = Uri.parse('wss://rt.dev/socket');
  return [
    NetworkLogEntry(
      id: 'rest',
      method: 'GET',
      url: Uri.parse('https://api.dev/users'),
      timestamp: fixtureNow.subtract(const Duration(hours: 2)),
      statusCode: 200,
      duration: const Duration(milliseconds: 90),
      responseBody: const NetworkLogBody(
        kind: NetworkBodyKind.text,
        content: '<users><user>Ada</user></users>',
        format: PayloadFormat.xml,
      ),
    ),
    NetworkLogEntry(
      id: 'gql',
      method: 'POST',
      url: Uri.parse('https://api.dev/graphql'),
      timestamp: fixtureNow.subtract(const Duration(seconds: 30)),
      statusCode: 200,
      duration: const Duration(milliseconds: 120),
      details: [
        GraphQLDetails(
          operations: const [
            GraphQLOperation(
              name: 'GetViewer',
              type: GraphQLOperationType.query,
              document: 'query GetViewer { viewer { id } }',
              variables: '{"id":"1"}',
            ),
          ],
          errors: [
            GraphQLError(
              message: 'Not allowed',
              path: const ['viewer', 'id'],
              code: 'FORBIDDEN',
            ),
          ],
          hasData: true,
        ),
      ],
    ),
    NetworkLogEntry(
      id: 'ws-open',
      method: 'WS',
      url: ws,
      timestamp: fixtureNow.subtract(const Duration(seconds: 20)),
      protocol: NetworkProtocol.webSocket,
      kind: NetworkEventKind.connection,
      lifecycle: ConnectionLifecycle.opened,
      connectionId: 'c1',
    ),
    NetworkLogEntry(
      id: 'ws-out',
      method: 'WS',
      url: ws,
      timestamp: fixtureNow.subtract(const Duration(seconds: 19)),
      protocol: NetworkProtocol.webSocket,
      kind: NetworkEventKind.message,
      direction: MessageDirection.outgoing,
      connectionId: 'c1',
      requestBody: const NetworkLogBody(
        kind: NetworkBodyKind.json,
        content: '{"subscribe":"prices"}',
      ),
      requestSize: 22,
    ),
    NetworkLogEntry(
      id: 'sse',
      method: 'SSE',
      url: Uri.parse('https://rt.dev/feed'),
      timestamp: fixtureNow.subtract(const Duration(seconds: 10)),
      protocol: NetworkProtocol.sse,
      kind: NetworkEventKind.message,
      direction: MessageDirection.incoming,
      connectionId: 'c2',
      details: const [SseDetails(eventType: 'price')],
      responseBody: const NetworkLogBody(
        kind: NetworkBodyKind.text,
        content: '42',
      ),
    ),
    NetworkLogEntry(
      id: 'grpc',
      method: 'POST',
      url: Uri.parse('https://api.dev/users.v1.Users/GetUser'),
      timestamp: fixtureNow.subtract(const Duration(seconds: 5)),
      statusCode: 200,
      protocol: NetworkProtocol.grpc,
      error: const NetworkLogError(
        type: NetworkErrorType.unknown,
        message: 'gRPC NOT_FOUND',
      ),
      details: const [
        GrpcDetails(
          service: 'users.v1.Users',
          method: 'GetUser',
          statusCode: 5,
          isWeb: true,
        ),
      ],
    ),
    NetworkLogEntry(
      id: 'mqtt',
      method: 'MQTT',
      url: Uri.parse('mqtts://broker.dev'),
      timestamp: fixtureNow,
      protocol: NetworkProtocol.mqtt,
      kind: NetworkEventKind.message,
      direction: MessageDirection.incoming,
      details: const [MqttDetails(topic: 'devices/1/state', qos: 1)],
    ),
  ];
}
