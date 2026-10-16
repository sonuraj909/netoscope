import 'json_helpers.dart';

/// Protocol-specific information attached to a `NetworkLogEntry`.
///
/// Netoscope ships details for GraphQL, webhooks, transfers, WebSockets, SSE,
/// gRPC and MQTT. The class is open so apps can attach their own details
/// through custom recorders. Values must already be redacted.
abstract class ProtocolDetails {
  /// Allows const subclasses.
  const ProtocolDetails();

  /// A stable identifier used in exports, such as `graphql`.
  String get type;

  /// A display title, such as `GraphQL`.
  String get label;

  /// Human-readable key/value pairs for the inspector and console.
  Map<String, String> describe();

  /// A JSON-compatible representation. Includes [type].
  Map<String, Object?> toJson();
}

/// Upload or download.
enum TransferDirection {
  /// Data sent by the app.
  upload,

  /// Data received by the app.
  download,
}

/// How much of a body was transferred, from client progress callbacks.
class TransferDetails extends ProtocolDetails {
  /// Creates transfer details.
  const TransferDetails({
    required this.direction,
    required this.bytesTransferred,
    this.totalBytes,
  });

  /// Restores details from [toJson] output.
  factory TransferDetails.fromJson(Map<String, Object?> json) =>
      TransferDetails(
        direction: readEnum(TransferDirection.values, json['direction'],
            TransferDirection.download),
        bytesTransferred: readInt(json['bytesTransferred']) ?? 0,
        totalBytes: readInt(json['totalBytes']),
      );

  /// Upload or download.
  final TransferDirection direction;

  /// Bytes transferred when the call finished.
  final int bytesTransferred;

  /// The expected total, when known.
  final int? totalBytes;

  /// The completed fraction between 0 and 1, when the total is known.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesTransferred / total).clamp(0, 1).toDouble();
  }

  /// Whether every expected byte was transferred.
  bool get isComplete => fraction == null || fraction == 1;

  @override
  String get type => 'transfer';

  @override
  String get label =>
      direction == TransferDirection.upload ? 'Upload' : 'Download';

  @override
  Map<String, String> describe() {
    final fraction = this.fraction;
    return {
      'Transferred': '$bytesTransferred bytes',
      if (totalBytes != null) 'Total': '$totalBytes bytes',
      if (fraction != null) 'Progress': '${(fraction * 100).round()}%',
    };
  }

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'direction': direction.name,
        'bytesTransferred': bytesTransferred,
        'totalBytes': totalBytes,
      };
}

/// WebSocket frame types.
enum WebSocketFrameType {
  /// A UTF-8 text frame.
  text,

  /// A binary frame.
  binary,
}

/// WebSocket connection or frame information.
class WebSocketDetails extends ProtocolDetails {
  /// Creates WebSocket details.
  const WebSocketDetails({
    this.frameType,
    this.closeCode,
    this.closeReason,
    this.subprotocol,
  });

  /// Restores details from [toJson] output.
  factory WebSocketDetails.fromJson(Map<String, Object?> json) =>
      WebSocketDetails(
        frameType: readEnumOrNull(WebSocketFrameType.values, json['frameType']),
        closeCode: readInt(json['closeCode']),
        closeReason: readAs<String>(json['closeReason']),
        subprotocol: readAs<String>(json['subprotocol']),
      );

  /// The frame type of a message event.
  final WebSocketFrameType? frameType;

  /// The close code of a closed connection.
  final int? closeCode;

  /// The close reason of a closed connection.
  final String? closeReason;

  /// The negotiated subprotocol, if any.
  final String? subprotocol;

  @override
  String get type => 'webSocket';

  @override
  String get label => 'WebSocket';

  @override
  Map<String, String> describe() => {
        if (frameType != null) 'Frame': frameType!.name,
        if (closeCode != null) 'Close code': '$closeCode',
        if (closeReason != null && closeReason!.isNotEmpty)
          'Close reason': closeReason!,
        if (subprotocol != null) 'Subprotocol': subprotocol!,
      };

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'frameType': frameType?.name,
        'closeCode': closeCode,
        'closeReason': closeReason,
        'subprotocol': subprotocol,
      };
}

/// A single Server-Sent Event.
class SseDetails extends ProtocolDetails {
  /// Creates SSE details.
  const SseDetails({this.eventType = 'message', this.eventId, this.retry});

  /// Restores details from [toJson] output.
  factory SseDetails.fromJson(Map<String, Object?> json) => SseDetails(
        eventType: readAs<String>(json['eventType']) ?? 'message',
        eventId: readAs<String>(json['eventId']),
        retry: readInt(json['retryMs']) == null
            ? null
            : Duration(milliseconds: readInt(json['retryMs'])!),
      );

  /// The `event:` field, `message` when absent.
  final String eventType;

  /// The `id:` field, if present.
  final String? eventId;

  /// The `retry:` reconnection delay, if present.
  final Duration? retry;

  @override
  String get type => 'sse';

  @override
  String get label => 'Server-Sent Event';

  @override
  Map<String, String> describe() => {
        'Event': eventType,
        if (eventId != null) 'ID': eventId!,
        if (retry != null) 'Retry': '${retry!.inMilliseconds} ms',
      };

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'eventType': eventType,
        'eventId': eventId,
        'retryMs': retry?.inMilliseconds,
      };
}

/// The cardinality of a gRPC call.
enum GrpcCallType {
  /// One request, one response.
  unary,

  /// One request, a stream of responses.
  serverStreaming,

  /// A stream of requests, one response.
  clientStreaming,

  /// Streams in both directions.
  bidiStreaming,

  /// Not known (for example gRPC-Web observed over HTTP).
  unknown,
}

/// gRPC or gRPC-Web call information.
class GrpcDetails extends ProtocolDetails {
  /// Creates gRPC details.
  const GrpcDetails({
    required this.service,
    required this.method,
    this.callType = GrpcCallType.unknown,
    this.statusCode,
    this.statusMessage,
    this.messagesSent,
    this.messagesReceived,
    this.isWeb = false,
  });

  /// Restores details from [toJson] output.
  factory GrpcDetails.fromJson(Map<String, Object?> json) => GrpcDetails(
        service: readAs<String>(json['service']) ?? '',
        method: readAs<String>(json['method']) ?? '',
        callType: readEnum(
            GrpcCallType.values, json['callType'], GrpcCallType.unknown),
        statusCode: readInt(json['statusCode']),
        statusMessage: readAs<String>(json['statusMessage']),
        messagesSent: readInt(json['messagesSent']),
        messagesReceived: readInt(json['messagesReceived']),
        isWeb: json['web'] == true,
      );

  /// The fully-qualified service, such as `helloworld.Greeter`.
  final String service;

  /// The method name, such as `SayHello`.
  final String method;

  /// The call cardinality.
  final GrpcCallType callType;

  /// The gRPC status code (0 is OK), when known.
  final int? statusCode;

  /// The gRPC status message, when present.
  final String? statusMessage;

  /// Messages sent by the client, when counted.
  final int? messagesSent;

  /// Messages received by the client, when counted.
  final int? messagesReceived;

  /// Whether the call used gRPC-Web over an HTTP client.
  final bool isWeb;

  /// The canonical name of [statusCode], such as `NOT_FOUND`.
  String? get statusName {
    final code = statusCode;
    if (code == null) return null;
    return code >= 0 && code < _statusNames.length
        ? _statusNames[code]
        : 'UNKNOWN($code)';
  }

  static const List<String> _statusNames = [
    'OK',
    'CANCELLED',
    'UNKNOWN',
    'INVALID_ARGUMENT',
    'DEADLINE_EXCEEDED',
    'NOT_FOUND',
    'ALREADY_EXISTS',
    'PERMISSION_DENIED',
    'RESOURCE_EXHAUSTED',
    'FAILED_PRECONDITION',
    'ABORTED',
    'OUT_OF_RANGE',
    'UNIMPLEMENTED',
    'INTERNAL',
    'UNAVAILABLE',
    'DATA_LOSS',
    'UNAUTHENTICATED',
  ];

  @override
  String get type => 'grpc';

  @override
  String get label => isWeb ? 'gRPC-Web' : 'gRPC';

  @override
  Map<String, String> describe() => {
        'Service': service,
        'Method': method,
        'Call type': callType.name,
        if (statusCode != null) 'Status': '$statusCode $statusName',
        if (statusMessage != null && statusMessage!.isNotEmpty)
          'Message': statusMessage!,
        if (messagesSent != null) 'Messages sent': '$messagesSent',
        if (messagesReceived != null) 'Messages received': '$messagesReceived',
      };

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'service': service,
        'method': method,
        'callType': callType.name,
        'statusCode': statusCode,
        'statusName': statusName,
        'statusMessage': statusMessage,
        'messagesSent': messagesSent,
        'messagesReceived': messagesReceived,
        'web': isWeb,
      };
}

/// MQTT session or message information.
class MqttDetails extends ProtocolDetails {
  /// Creates MQTT details.
  const MqttDetails({
    this.topic,
    this.qos,
    this.retained,
    this.clientId,
    this.packetId,
  });

  /// Restores details from [toJson] output.
  factory MqttDetails.fromJson(Map<String, Object?> json) => MqttDetails(
        topic: readAs<String>(json['topic']),
        qos: readInt(json['qos']),
        retained: readAs<bool>(json['retained']),
        clientId: readAs<String>(json['clientId']),
        packetId: readInt(json['packetId']),
      );

  /// The topic (or topic filter for subscriptions).
  final String? topic;

  /// The quality-of-service level (0, 1 or 2).
  final int? qos;

  /// Whether the message was retained.
  final bool? retained;

  /// The client identifier of the session.
  final String? clientId;

  /// The packet identifier, when known.
  final int? packetId;

  @override
  String get type => 'mqtt';

  @override
  String get label => 'MQTT';

  @override
  Map<String, String> describe() => {
        if (topic != null) 'Topic': topic!,
        if (qos != null) 'QoS': '$qos',
        if (retained != null) 'Retained': '$retained',
        if (clientId != null) 'Client ID': clientId!,
        if (packetId != null) 'Packet ID': '$packetId',
      };

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'topic': topic,
        'qos': qos,
        'retained': retained,
        'clientId': clientId,
        'packetId': packetId,
      };
}
