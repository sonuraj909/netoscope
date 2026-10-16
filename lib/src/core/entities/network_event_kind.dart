/// The transport or protocol an event belongs to.
enum NetworkProtocol {
  /// Plain HTTP(S), including REST, GraphQL-over-HTTP and webhooks.
  http('HTTP'),

  /// WebSocket connections and frames.
  webSocket('WebSocket'),

  /// Server-Sent Events (`text/event-stream`).
  sse('SSE'),

  /// gRPC and gRPC-Web calls.
  grpc('gRPC'),

  /// MQTT sessions and messages.
  mqtt('MQTT'),

  /// Anything else reported through a custom recorder.
  other('Other');

  const NetworkProtocol(this.label);

  /// A short display label.
  final String label;
}

/// The shape of an event.
enum NetworkEventKind {
  /// A request with its response or failure (an HTTP call, a gRPC unary
  /// call, a webhook delivery attempt).
  exchange,

  /// A connection lifecycle change (opened, closed, failed).
  connection,

  /// A single message on a long-lived connection.
  message,
}

/// Which way a message travelled, from the app's point of view.
enum MessageDirection {
  /// Sent by the app.
  outgoing,

  /// Received by the app.
  incoming,
}

/// A connection lifecycle stage.
enum ConnectionLifecycle {
  /// The connection was established.
  opened,

  /// The connection was closed normally (by either side).
  closed,

  /// The connection failed or was dropped.
  failed,
}
