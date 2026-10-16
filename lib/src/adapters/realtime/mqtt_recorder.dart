import '../../core/entities/network_event_kind.dart';
import '../../core/entities/protocol_details.dart';
import 'connection_recorder.dart';

/// Records an MQTT session.
///
/// Netoscope does not depend on an MQTT client. Call these methods from
/// your client's callbacks, for example with `package:mqtt_client`:
///
/// ```dart
/// final mqtt = netoscope.mqtt(Uri.parse('mqtts://broker.example.com'),
///     clientId: 'app-1');
/// client.onConnected = () => mqtt.connected();
/// client.onDisconnected = () => mqtt.disconnected();
/// client.updates!.listen((messages) {
///   for (final m in messages) {
///     final payload = (m.payload as MqttPublishMessage).payload.message;
///     mqtt.received(m.topic, payload);
///   }
/// });
/// ```
class MqttRecorder extends ConnectionRecorder {
  /// Creates a recorder. Use `Netoscope.mqtt` instead.
  MqttRecorder(
    super.capture, {
    required super.url,
    this.clientId,
    super.ignoreMessage,
  }) : super(protocol: NetworkProtocol.mqtt, label: 'MQTT');

  /// The client identifier.
  final String? clientId;

  /// Records a successful CONNECT.
  void connected() => opened(details: [MqttDetails(clientId: clientId)]);

  /// Records a disconnect.
  void disconnected({String? closedBy}) => closed(
        closedBy: closedBy,
        details: [MqttDetails(clientId: clientId)],
      );

  /// Records a SUBSCRIBE.
  void subscribed(String topicFilter, {int? qos}) => message(
        MessageDirection.outgoing,
        null,
        details: [MqttDetails(topic: topicFilter, qos: qos)],
        metadata: const {'packet': 'SUBSCRIBE'},
      );

  /// Records an outgoing PUBLISH.
  void published(
    String topic,
    Object? payload, {
    int? qos,
    bool? retained,
    int? packetId,
  }) =>
      message(
        MessageDirection.outgoing,
        payload,
        details: [
          MqttDetails(
            topic: topic,
            qos: qos,
            retained: retained,
            packetId: packetId,
          ),
        ],
        metadata: const {'packet': 'PUBLISH'},
      );

  /// Records an incoming PUBLISH.
  void received(
    String topic,
    Object? payload, {
    int? qos,
    bool? retained,
    int? packetId,
  }) =>
      message(
        MessageDirection.incoming,
        payload,
        details: [
          MqttDetails(
            topic: topic,
            qos: qos,
            retained: retained,
            packetId: packetId,
          ),
        ],
        metadata: const {'packet': 'PUBLISH'},
      );
}
