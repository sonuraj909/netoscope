import 'dart:async';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../core/entities/protocol_details.dart';
import '../../security/body_capture.dart';
import '../log_capture.dart';

/// Records the lifecycle and messages of one long-lived connection.
///
/// This is the protocol-agnostic contract that real-time integrations call.
/// Obtain one from `Netoscope.connection`, or a protocol-specific subclass
/// from `Netoscope.webSocket`, `Netoscope.serverSentEvents` or
/// `Netoscope.mqtt`.
///
/// When logging is disabled or the URL is excluded, every method is a no-op.
/// Recording never throws.
class ConnectionRecorder {
  /// Creates a recorder. Use the `Netoscope` factory methods instead.
  ConnectionRecorder(
    this.capture, {
    required this.protocol,
    required Uri url,
    required String label,
    Map<String, String> requestHeaders = const {},
    this.ignoreMessage,
  })  : _url = url,
        _label = label,
        _requestHeaders = requestHeaders,
        connectionId = capture.nextId(),
        isActive = capture.shouldLog(url) {
    _lifetime.start();
  }

  /// The shared capture policy.
  final LogCapture capture;

  /// The protocol of this connection.
  final NetworkProtocol protocol;

  /// Groups every event of this connection.
  final String connectionId;

  /// Whether events are being recorded.
  final bool isActive;

  /// Messages for which this returns `true` (for example heartbeats) are
  /// counted but not recorded.
  final bool Function(Object? message)? ignoreMessage;

  final Uri _url;
  final String _label;
  final Map<String, String> _requestHeaders;
  final Stopwatch _lifetime = Stopwatch();
  bool _opened = false;
  bool _ended = false;
  int _sent = 0;
  int _received = 0;

  /// Messages sent so far.
  int get messagesSent => _sent;

  /// Messages received so far.
  int get messagesReceived => _received;

  /// Whether [closed] or [failed] has been recorded.
  bool get isEnded => _ended;

  /// Records that the connection was established.
  void opened({
    int? statusCode,
    Map<String, String> responseHeaders = const {},
    List<ProtocolDetails> details = const [],
  }) {
    if (!isActive || _opened) return;
    _opened = true;
    _lifetime
      ..reset()
      ..start();
    _record(
      kind: NetworkEventKind.connection,
      lifecycle: ConnectionLifecycle.opened,
      statusCode: statusCode,
      requestHeaders: _requestHeaders,
      responseHeaders: responseHeaders,
      details: details,
    );
  }

  /// Records a normal close. Only the first close or failure is recorded.
  void closed({
    List<ProtocolDetails> details = const [],
    String? closedBy,
  }) {
    if (!isActive || _ended) return;
    _ended = true;
    _record(
      kind: NetworkEventKind.connection,
      lifecycle: ConnectionLifecycle.closed,
      duration: _lifetime.elapsed,
      details: details,
      metadata: {
        ..._counts(),
        if (closedBy != null) 'closedBy': closedBy,
      },
    );
  }

  /// Records a failure. Only the first close or failure is recorded.
  void failed(Object error, {List<ProtocolDetails> details = const []}) {
    if (!isActive || _ended) return;
    _ended = true;
    final type = error is TimeoutException
        ? NetworkErrorType.timeout
        : NetworkErrorType.connection;
    _record(
      kind: NetworkEventKind.connection,
      lifecycle: ConnectionLifecycle.failed,
      duration: _lifetime.elapsed,
      error: capture.error(type, error.toString()),
      details: details,
      metadata: _counts(),
    );
  }

  /// Records one message. [payload] may be a string, bytes, a map or list,
  /// or any object with `toJson()`; it is redacted and truncated like HTTP
  /// bodies.
  void message(
    MessageDirection direction,
    Object? payload, {
    String? contentType,
    List<ProtocolDetails> details = const [],
    Map<String, String> metadata = const {},
  }) {
    if (!isActive) return;
    if (direction == MessageDirection.outgoing) {
      _sent++;
    } else {
      _received++;
    }
    if (!capture.config.captureRealtimeMessages) return;
    try {
      if (ignoreMessage?.call(payload) ?? false) return;
    } catch (_) {
      // A failing filter records the message.
    }
    final context = capture.payload(
      _url,
      direction,
      contentType: contentType,
      protocol: protocol,
    );
    final outgoing = direction == MessageDirection.outgoing;
    final body = outgoing
        ? capture.requestBody((b) => b.capture(payload, context: context))
        : capture.responseBody((b) => b.capture(payload, context: context));
    final size = BodyCapture.sizeOf(payload);
    _record(
      kind: NetworkEventKind.message,
      direction: direction,
      requestBody: outgoing ? body : null,
      responseBody: outgoing ? null : body,
      requestSize: outgoing ? size : null,
      responseSize: outgoing ? null : size,
      details: details,
      metadata: metadata,
    );
  }

  Map<String, String> _counts() => {
        'messagesSent': '$_sent',
        'messagesReceived': '$_received',
      };

  void _record({
    required NetworkEventKind kind,
    ConnectionLifecycle? lifecycle,
    MessageDirection? direction,
    int? statusCode,
    Duration? duration,
    NetworkLogError? error,
    Map<String, String> requestHeaders = const {},
    Map<String, String> responseHeaders = const {},
    NetworkLogBody? requestBody,
    NetworkLogBody? responseBody,
    int? requestSize,
    int? responseSize,
    List<ProtocolDetails> details = const [],
    Map<String, String> metadata = const {},
  }) {
    capture.record(
      () => NetworkLogEntry(
        id: capture.nextId(),
        method: _label,
        url: capture.url(_url),
        timestamp: DateTime.now(),
        protocol: protocol,
        kind: kind,
        lifecycle: lifecycle,
        direction: direction,
        connectionId: connectionId,
        statusCode: statusCode,
        duration: duration,
        error: error,
        requestHeaders: capture.headers(requestHeaders),
        responseHeaders: capture.headers(responseHeaders),
        requestBody: requestBody,
        responseBody: responseBody,
        requestSize: requestSize,
        responseSize: responseSize,
        details: details,
        tags: capture.currentTags(),
        metadata: capture.redactor.redactHeaders(metadata),
      ),
    );
  }
}
