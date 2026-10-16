import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'adapters/dio/dio_network_logger.dart';
import 'adapters/http/http_network_logger.dart';
import 'adapters/log_capture.dart';
import 'adapters/realtime/connection_recorder.dart';
import 'adapters/realtime/grpc_call_recorder.dart';
import 'adapters/realtime/mqtt_recorder.dart';
import 'adapters/realtime/sse_recorder.dart';
import 'adapters/realtime/web_socket_recorder.dart';
import 'adapters/webhook_importer.dart';
import 'config/network_logger_config.dart';
import 'core/contracts/network_log_sink.dart';
import 'core/contracts/network_log_store.dart';
import 'core/entities/network_event_kind.dart';
import 'core/entities/network_log_entry.dart';
import 'core/entities/protocol_details.dart';
import 'core/usecases/clear_network_logs.dart';
import 'core/usecases/get_network_logs.dart';
import 'core/usecases/record_network_log.dart';
import 'data/export/network_log_json_exporter.dart';
import 'data/sinks/console_network_log_sink.dart';
import 'data/storage/in_memory_network_log_store.dart';
import 'protocols/webhook/webhook_delivery_record.dart';

/// The entry point to Netoscope.
///
/// Create one instance, typically at app start-up, and attach it to your
/// HTTP clients:
///
/// ```dart
/// final netoscope = Netoscope();
/// dio.interceptors.add(netoscope.dioInterceptor);
/// final client = netoscope.httpClient();
/// ```
///
/// Every attached client records into the same history, which the console
/// output and the optional inspector read from.
class Netoscope {
  /// Creates a logger.
  ///
  /// By default history is kept in an [InMemoryNetworkLogStore] bounded by
  /// [NetworkLoggerConfig.maxHistorySize], and a console sink is added unless
  /// [NetworkLoggerConfig.consoleLogLevel] is [ConsoleLogLevel.none]. Pass
  /// [store] to supply your own history, and [sinks] to forward entries
  /// elsewhere.
  factory Netoscope({
    NetworkLoggerConfig config = const NetworkLoggerConfig(),
    NetworkLogStore? store,
    Iterable<NetworkLogSink> sinks = const [],
  }) {
    final ownedStore = store == null
        ? InMemoryNetworkLogStore(maxEntries: config.maxHistorySize)
        : null;
    return Netoscope._(
      config,
      store ?? ownedStore!,
      ownedStore,
      [
        if (config.consoleLogLevel != ConsoleLogLevel.none)
          ConsoleNetworkLogSink(
            level: config.consoleLogLevel,
            slowRequestThreshold: config.slowRequestThreshold,
          ),
        ...sinks,
      ],
    );
  }

  Netoscope._(
    this.config,
    NetworkLogStore store,
    this._ownedStore,
    List<NetworkLogSink> sinks,
  )   : _getLogs = GetNetworkLogs(store),
        _clearLogs = ClearNetworkLogs(store),
        _capture = LogCapture(
          config: config,
          record: RecordNetworkLog(store, sinks: sinks),
        );

  /// Add `extra: {Netoscope.skipLoggingKey: true}` to a Dio request's
  /// options to keep that request out of the logs.
  static const String skipLoggingKey = netoscopeSkipKey;

  /// Add `extra: {Netoscope.webhookKey: WebhookAttempt(...)}` to a Dio
  /// request's options to record it as a webhook delivery attempt.
  static const String webhookKey = netoscopeWebhookKey;

  /// The active configuration.
  final NetworkLoggerConfig config;

  final InMemoryNetworkLogStore? _ownedStore;
  final GetNetworkLogs _getLogs;
  final ClearNetworkLogs _clearLogs;
  final LogCapture _capture;

  /// Whether calls are being recorded in the current build mode.
  bool get isEnabled => config.isEnabled;

  /// Whether the inspector UI should be offered.
  bool get isInspectorAvailable => isEnabled && config.showInspector;

  /// Recorded calls, newest first.
  List<NetworkLogEntry> get logs => _getLogs();

  /// Emits the full history, newest first, whenever it changes.
  Stream<List<NetworkLogEntry>> get logChanges => _getLogs.watch();

  /// Removes all recorded calls.
  void clearLogs() => _clearLogs();

  /// The current history as indented JSON. Values are already redacted.
  String exportJson() => exportNetworkLogsAsJson(logs);

  /// A Dio interceptor recording into this logger.
  ///
  /// Add it last so it sees the final headers set by other interceptors.
  /// When logging is disabled this is a pass-through interceptor.
  late final Interceptor dioInterceptor =
      isEnabled ? DioNetworkLogger(_capture) : Interceptor();

  /// Returns a `package:http` client recording into this logger.
  ///
  /// Wraps [inner], or a new `http.Client()` when omitted. Closing the
  /// returned client closes [inner]. When logging is disabled, [inner] (or the
  /// new client) is returned unwrapped.
  http.Client httpClient([http.Client? inner]) {
    final client = inner ?? http.Client();
    return isEnabled ? HttpNetworkLogger(client, _capture) : client;
  }

  /// Returns a recorder for a WebSocket connection to [url].
  ///
  /// [headers] are the handshake headers, if known. Messages for which
  /// [ignoreMessage] returns `true` (such as heartbeats) are counted but not
  /// recorded.
  WebSocketRecorder webSocket(
    Uri url, {
    Map<String, String> headers = const {},
    bool Function(Object? message)? ignoreMessage,
  }) =>
      WebSocketRecorder(
        _capture,
        url: url,
        requestHeaders: headers,
        ignoreMessage: ignoreMessage,
      );

  /// Returns a recorder for a Server-Sent Events connection to [url].
  ///
  /// Not needed for clients from [httpClient], which record event streams
  /// automatically.
  SseRecorder serverSentEvents(
    Uri url, {
    Map<String, String> headers = const {},
    bool Function(Object? message)? ignoreMessage,
  }) =>
      SseRecorder(
        _capture,
        url: url,
        requestHeaders: headers,
        ignoreMessage: ignoreMessage,
      );

  /// Returns a recorder for an MQTT session with the broker at [url].
  MqttRecorder mqtt(
    Uri url, {
    String? clientId,
    bool Function(Object? message)? ignoreMessage,
  }) =>
      MqttRecorder(
        _capture,
        url: url,
        clientId: clientId,
        ignoreMessage: ignoreMessage,
      );

  /// Returns a recorder for one gRPC call to [path]
  /// (`/package.Service/Method`) on [host].
  ///
  /// [metadata] is recorded like request headers (and redacted).
  /// [encodeMessage] converts messages into something inspectable, for
  /// example `(m) => (m as GeneratedMessage).toProto3Json()`.
  GrpcCallRecorder grpcCall(
    String path, {
    Uri? host,
    GrpcCallType callType = GrpcCallType.unary,
    Map<String, String> metadata = const {},
    Object? Function(Object? message)? encodeMessage,
  }) =>
      GrpcCallRecorder(
        _capture,
        path: path,
        host: host,
        callType: callType,
        metadata: metadata,
        encodeMessage: encodeMessage,
      );

  /// Returns a recorder for a connection of any other protocol, labelled
  /// [label] in the inspector.
  ConnectionRecorder connection(
    Uri url, {
    NetworkProtocol protocol = NetworkProtocol.other,
    String label = 'CONN',
    Map<String, String> headers = const {},
    bool Function(Object? message)? ignoreMessage,
  }) =>
      ConnectionRecorder(
        _capture,
        protocol: protocol,
        url: url,
        label: label,
        requestHeaders: headers,
        ignoreMessage: ignoreMessage,
      );

  /// Adds webhook delivery attempts reported by a backend to the history.
  ///
  /// A Flutter app cannot observe incoming server-to-server webhooks; use
  /// this to inspect delivery logs your backend exposes. Records are
  /// redacted like captured traffic.
  void importWebhookDeliveries(Iterable<WebhookDeliveryRecord> records) {
    if (!isEnabled) return;
    WebhookImporter(_capture).import(records);
  }

  /// Releases the history created by this instance. A store passed to the
  /// constructor is left untouched.
  Future<void> dispose() async => _ownedStore?.dispose();
}
