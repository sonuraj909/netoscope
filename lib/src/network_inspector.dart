import 'dart:async';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'adapters/dio/dio_network_logger.dart';
import 'adapters/external/external_network_call.dart' as ext;
import 'adapters/http/http_network_logger.dart';
import 'adapters/io/dart_io_capture.dart';
import 'adapters/log_capture.dart';
import 'adapters/realtime/connection_recorder.dart';
import 'adapters/realtime/grpc_call_recorder.dart';
import 'adapters/realtime/mqtt_recorder.dart';
import 'adapters/realtime/sse_recorder.dart';
import 'adapters/realtime/web_socket_recorder.dart';
import 'adapters/webhook_importer.dart';
import 'config/netoscope_settings.dart';
import 'config/network_logger_config.dart';
import 'core/contracts/network_activity_notifier.dart';
import 'core/contracts/network_log_sink.dart';
import 'core/contracts/network_log_store.dart';
import 'core/entities/network_event_kind.dart';
import 'core/entities/network_log_entry.dart';
import 'core/entities/protocol_details.dart';
import 'core/entities/traffic_insights.dart';
import 'core/entities/traffic_statistics.dart';
import 'core/usecases/clear_network_logs.dart';
import 'core/usecases/get_network_logs.dart';
import 'core/usecases/record_network_log.dart';
import 'data/export/har_exporter.dart';
import 'data/export/network_log_json_exporter.dart';
import 'data/notifications/activity_notification_controller.dart';
import 'data/sinks/console_network_log_sink.dart';
import 'data/storage/in_memory_network_log_store.dart';
import 'protocols/webhook/webhook_delivery_record.dart';

/// A file produced by the inspector's export menu.
class NetoscopeExport {
  /// Creates an export.
  const NetoscopeExport({
    required this.fileName,
    required this.mimeType,
    required this.content,
  });

  /// A suggested file name, such as `netoscope-2026-10-16.har`.
  final String fileName;

  /// The MIME type, such as `application/json`.
  final String mimeType;

  /// The file content (already redacted).
  final String content;
}

/// Delivers an export, for example by writing it to a temporary file and
/// opening the platform share sheet.
typedef NetoscopeExportHandler = Future<void> Function(NetoscopeExport export);

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
  ///
  /// Pass [notifier] (or call [attachNotifier] later) to show activity in a
  /// notification, updated at most once per [notificationInterval].
  factory Netoscope({
    NetworkLoggerConfig config = const NetworkLoggerConfig(),
    NetworkLogStore? store,
    Iterable<NetworkLogSink> sinks = const [],
    NetworkActivityNotifier? notifier,
    Duration notificationInterval = const Duration(seconds: 1),
    NetoscopeExportHandler? exportHandler,
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
            colors: config.consoleColors,
            slowRequestThreshold: config.slowRequestThreshold,
          ),
        ...sinks,
      ],
      notificationInterval,
    )
      ..exportHandler = exportHandler
      ..attachNotifier(notifier);
  }

  Netoscope._(
    this.config,
    NetworkLogStore store,
    this._ownedStore,
    List<NetworkLogSink> sinks,
    this.notificationInterval,
  )   : _settings = NetoscopeSettings(
          floatingButton: config.showFloatingButton,
          notification: config.showNotification,
          themeMode: config.inspectorThemeMode,
        ),
        _getLogs = GetNetworkLogs(store),
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

  /// Add `extra: {Netoscope.tagsKey: 'checkout'}` (or a list of tags) to a
  /// Dio request's options to tag that request.
  static const String tagsKey = netoscopeTagsKey;

  /// The active configuration.
  final NetworkLoggerConfig config;

  final InMemoryNetworkLogStore? _ownedStore;
  final GetNetworkLogs _getLogs;
  final ClearNetworkLogs _clearLogs;
  final LogCapture _capture;
  final StreamController<NetoscopeSettings> _settingsChanges =
      StreamController.broadcast();
  NetoscopeSettings _settings;
  ActivityNotificationController? _notifications;
  StreamSubscription<List<NetworkLogEntry>>? _historySubscription;
  DartIoCapture? _dartIo;

  /// The minimum time between notification updates.
  final Duration notificationInterval;

  /// Whether logging is enabled for this build (see
  /// [NetworkLoggerConfig.enabled]). When `false`, nothing can be switched on
  /// at runtime.
  bool get isEnabled => config.isEnabled;

  /// Whether the inspector UI should be offered.
  bool get isInspectorAvailable => isEnabled && config.showInspector;

  /// The current runtime switches.
  NetoscopeSettings get settings => _settings;

  /// Emits the settings whenever a switch changes or a notifier is attached.
  Stream<NetoscopeSettings> get settingsChanges => _settingsChanges.stream;

  /// Whether new activity is being recorded right now.
  bool get isRecording => isEnabled && _settings.recording;

  /// Whether the floating inspector button should be shown.
  bool get isFloatingButtonVisible =>
      isInspectorAvailable && _settings.floatingButton;

  /// Whether a notifier is attached.
  bool get hasNotifier => _notifications != null;

  /// Whether the activity notification is currently on.
  bool get isNotificationActive => _notifications?.isActive ?? false;

  /// Pauses (`false`) or resumes (`true`) recording. History is kept.
  void setLoggingEnabled(bool enabled) =>
      updateSettings(_settings.copyWith(recording: enabled));

  /// Shows or hides the floating inspector button.
  void setFloatingButtonEnabled(bool enabled) =>
      updateSettings(_settings.copyWith(floatingButton: enabled));

  /// Shows or hides the activity notification (needs a notifier).
  void setNotificationEnabled(bool enabled) =>
      updateSettings(_settings.copyWith(notification: enabled));

  /// Switches the inspector between following the host app's theme, light
  /// and dark. Open inspector screens update immediately.
  void setInspectorThemeMode(InspectorThemeMode mode) =>
      updateSettings(_settings.copyWith(themeMode: mode));

  /// Replaces all runtime switches at once. Ignored when logging is
  /// disabled for this build.
  void updateSettings(NetoscopeSettings settings) {
    if (!isEnabled || settings == _settings) return;
    final recordingChanged = settings.recording != _settings.recording;
    _settings = settings;
    _capture.recording = settings.recording;
    _syncNotification();
    if (recordingChanged) _notifications?.refresh();
    _settingsChanges.add(settings);
  }

  /// Attaches (or, with `null`, detaches) the notifier that shows activity
  /// outside the app UI. Ignored when logging is disabled for this build.
  void attachNotifier(NetworkActivityNotifier? notifier) {
    unawaited(_historySubscription?.cancel());
    _historySubscription = null;
    _notifications?.dispose();
    _notifications = null;
    if (notifier != null && isEnabled) {
      final controller = ActivityNotificationController(
        notifier: notifier,
        entries: () => logs,
        isRecording: () => isRecording,
        interval: notificationInterval,
      );
      _notifications = controller;
      _historySubscription =
          logChanges.listen((_) => controller.onHistoryChanged());
      _syncNotification();
    }
    if (!_settingsChanges.isClosed) _settingsChanges.add(_settings);
  }

  void _syncNotification() =>
      _notifications?.setActive(isEnabled && _settings.notification);

  /// Recorded calls, newest first.
  List<NetworkLogEntry> get logs => _getLogs();

  /// Emits the full history, newest first, whenever it changes.
  Stream<List<NetworkLogEntry>> get logChanges => _getLogs.watch();

  /// Removes all recorded calls.
  void clearLogs() => _clearLogs();

  /// Duplicate and N+1 requests in the current history, detected with
  /// [NetworkLoggerConfig.trafficAnalyzer].
  TrafficInsights analyzeTraffic() => config.trafficAnalyzer.analyze(logs);

  /// Aggregate statistics for the current history.
  TrafficStatistics statistics() => TrafficStatistics.from(
        logs,
        slowThreshold: config.slowRequestThreshold,
      );

  /// The current history as indented JSON. Values are already redacted.
  String exportJson() => exportNetworkLogsAsJson(logs);

  /// The current HTTP calls as a HAR 1.2 document (importable into browser
  /// DevTools, Charles, Proxyman or Postman). Values are already redacted.
  String exportHar() => exportNetworkLogsAsHar(logs);

  /// Shares exports from the inspector (for example through a share sheet).
  /// When `null`, the inspector offers copying only. See
  /// [NetoscopeExport].
  NetoscopeExportHandler? exportHandler;

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

  /// Tags every call started from now on with [tag] until [removeTag] or
  /// [clearTags]. Useful for flows: `addTag('checkout')` … `removeTag(…)`.
  void addTag(String tag) => _capture.addTag(tag);

  /// Stops tagging new calls with [tag].
  void removeTag(String tag) => _capture.removeTag(tag);

  /// Removes all tags added with [addTag].
  void clearTags() => _capture.clearTags();

  /// The tags added with [addTag].
  Set<String> get activeTags => _capture.globalTags;

  /// Runs [body] and tags every call started inside it, including calls in
  /// its asynchronous continuations, with [tags] (a `String` or an
  /// `Iterable<String>`). Nested calls combine tags.
  ///
  /// ```dart
  /// await netoscope.tagged('login-flow', () async {
  ///   await api.login();
  ///   await api.loadProfile();
  /// });
  /// ```
  R tagged<R>(Object tags, R Function() body) {
    final outer = Zone.current[netoscopeTagsZoneKey];
    return runZoned(
      body,
      zoneValues: {
        netoscopeTagsZoneKey: <String>{
          if (outer is Iterable<String>) ...outer,
          if (tags is String) tags,
          if (tags is Iterable) ...tags.whereType<String>(),
        },
      },
    );
  }

  /// Records an HTTP call observed outside Dart, such as by native code.
  /// It is redacted, truncated and inspected like captured calls.
  void recordExternalCall(ext.ExternalNetworkCall call) =>
      ext.recordExternalCall(_capture, call);

  /// Records calls made with `dart:io`'s `HttpClient`: directly, through
  /// `IOClient`, `Image.network`, third-party SDKs or any other library.
  ///
  /// Installs a global `HttpOverrides` that wraps every `HttpClient` created
  /// afterwards. Clients created earlier are not captured, so call this
  /// early, for example at the start of `main`. A previously installed
  /// `HttpOverrides` keeps working. Calls already recorded by
  /// [dioInterceptor] or [httpClient] are not recorded twice.
  ///
  /// Returns `false` (and does nothing) on the web or when logging is
  /// disabled for this build.
  bool captureDartIo() {
    if (!isEnabled) return false;
    if (_dartIo != null) return true;
    _dartIo = installDartIoCapture(_capture);
    return _dartIo != null;
  }

  /// Stops [captureDartIo] and restores the previous `HttpOverrides`.
  /// New `HttpClient`s are no longer wrapped, even when overrides installed
  /// later still delegate to Netoscope's. `HttpClient`s created while
  /// capture was on keep recording.
  void stopCapturingDartIo() {
    _dartIo?.uninstall();
    _dartIo = null;
  }

  /// Whether [captureDartIo] is active.
  bool get isCapturingDartIo => _dartIo != null;

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

  /// Removes the notification, closes the settings stream and releases the
  /// history created by this instance. A store passed to the constructor is
  /// left untouched.
  Future<void> dispose() async {
    stopCapturingDartIo();
    await _historySubscription?.cancel();
    _notifications?.dispose();
    await _settingsChanges.close();
    await _ownedStore?.dispose();
  }
}
