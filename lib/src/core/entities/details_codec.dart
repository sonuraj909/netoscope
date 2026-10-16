import 'graphql_details.dart';
import 'json_helpers.dart';
import 'protocol_details.dart';
import 'webhook_details.dart';

/// Restores built-in [ProtocolDetails] from their `toJson` output. Returns
/// `null` for unknown (custom) types.
ProtocolDetails? protocolDetailsFromJson(Object? value) {
  final json = readObject(value);
  if (json == null) return null;
  return switch (json['type']) {
    'graphql' => GraphQLDetails.fromJson(json),
    'webhook' => WebhookDetails.fromJson(json),
    'grpc' => GrpcDetails.fromJson(json),
    'sse' => SseDetails.fromJson(json),
    'webSocket' => WebSocketDetails.fromJson(json),
    'mqtt' => MqttDetails.fromJson(json),
    'transfer' => TransferDetails.fromJson(json),
    _ => null,
  };
}
