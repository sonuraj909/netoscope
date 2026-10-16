import 'dart:async';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../core/entities/protocol_details.dart';
import '../../protocols/grpc/grpc_web_inspector.dart';
import '../log_capture.dart';

/// Records one gRPC call.
///
/// Netoscope does not depend on `package:grpc`; call these methods from a
/// `ClientInterceptor` (see the README for a complete example). One
/// exchange entry is recorded when the call finishes. For streaming calls,
/// each message is also recorded when real-time message capture is on.
///
/// gRPC messages are usually generated protobuf classes without `toJson`.
/// Pass `encodeMessage` (for example `(m) => (m as GeneratedMessage)
/// .toProto3Json()`) so payloads can be shown; otherwise only their type is
/// recorded.
class GrpcCallRecorder {
  /// Creates a recorder. Use `Netoscope.grpcCall` instead.
  GrpcCallRecorder(
    this._capture, {
    required String path,
    Uri? host,
    this.callType = GrpcCallType.unary,
    Map<String, String> metadata = const {},
    Object? Function(Object? message)? encodeMessage,
  })  : _url = (host ?? Uri(scheme: 'grpc', host: 'unknown')).replace(
          path: path.startsWith('/') ? path : '/$path',
        ),
        _metadata = metadata,
        _encode = encodeMessage,
        _id = _capture.nextId(),
        _startedAt = DateTime.now(),
        isActive = _capture.shouldLog(
          (host ?? Uri(scheme: 'grpc', host: 'unknown')).replace(path: path),
        ) {
    _stopwatch.start();
  }

  final LogCapture _capture;
  final Uri _url;
  final Map<String, String> _metadata;
  final Object? Function(Object? message)? _encode;
  final String _id;
  final DateTime _startedAt;
  final Stopwatch _stopwatch = Stopwatch();
  NetworkLogBody? _firstSent;
  NetworkLogBody? _firstReceived;
  int _sent = 0;
  int _received = 0;
  bool _finished = false;

  /// The call cardinality.
  final GrpcCallType callType;

  /// Whether this call is being recorded.
  final bool isActive;

  bool get _streaming => callType != GrpcCallType.unary;

  /// Records a request message.
  void sent(Object? message) => _message(MessageDirection.outgoing, message);

  /// Records a response message.
  void received(Object? message) =>
      _message(MessageDirection.incoming, message);

  /// Records completion with a gRPC [statusCode] (0 is OK).
  void finish({
    int statusCode = 0,
    String? statusMessage,
    Map<String, String> trailers = const {},
  }) =>
      _finish(
          statusCode: statusCode,
          statusMessage: statusMessage,
          trailers: trailers);

  /// Records a failure that has no gRPC status (for example a transport
  /// error or cancellation).
  void fail(Object error) => _finish(failure: error);

  void _message(MessageDirection direction, Object? message) {
    if (!isActive || _finished) return;
    final outgoing = direction == MessageDirection.outgoing;
    if (outgoing) {
      _sent++;
    } else {
      _received++;
    }
    final isFirst = outgoing ? _sent == 1 : _received == 1;
    final record = _streaming && _capture.config.captureRealtimeMessages;
    if (!isFirst && !record) return;
    final body = _body(direction, message);
    if (isFirst) {
      if (outgoing) {
        _firstSent = body;
      } else {
        _firstReceived = body;
      }
    }
    if (!record) return;
    _capture.record(
      () => NetworkLogEntry(
        id: _capture.nextId(),
        method: 'GRPC',
        url: _capture.url(_url),
        timestamp: DateTime.now(),
        protocol: NetworkProtocol.grpc,
        kind: NetworkEventKind.message,
        direction: direction,
        connectionId: _id,
        requestBody: outgoing ? body : null,
        responseBody: outgoing ? null : body,
        details: [_details()],
      ),
    );
  }

  NetworkLogBody? _body(MessageDirection direction, Object? message) {
    Object? payload = message;
    try {
      if (_encode != null) payload = _encode(message);
    } catch (_) {
      payload = message;
    }
    final context = _capture.payload(
      _url,
      direction,
      contentType: payload is List<int> ? 'application/x-protobuf' : null,
      protocol: NetworkProtocol.grpc,
    );
    return direction == MessageDirection.outgoing
        ? _capture.requestBody((b) => b.capture(payload, context: context))
        : _capture.responseBody((b) => b.capture(payload, context: context));
  }

  GrpcDetails _details({int? statusCode, String? statusMessage}) {
    final segments = _url.pathSegments.where((s) => s.isNotEmpty).toList();
    return GrpcDetails(
      service: segments.length >= 2 ? segments[segments.length - 2] : '',
      method: segments.isEmpty ? '' : segments.last,
      callType: callType,
      statusCode: statusCode,
      statusMessage: statusMessage,
      messagesSent: _sent,
      messagesReceived: _received,
    );
  }

  void _finish({
    int? statusCode,
    String? statusMessage,
    Map<String, String> trailers = const {},
    Object? failure,
  }) {
    if (!isActive || _finished) return;
    _finished = true;
    final duration = _stopwatch.elapsed;
    _capture.record(() {
      final details = _details(
        statusCode: statusCode,
        statusMessage: statusMessage == null
            ? null
            : _capture.redactor.redactText(statusMessage),
      );
      final NetworkLogError? error;
      if (failure != null) {
        error = _capture.error(
          failure is TimeoutException
              ? NetworkErrorType.timeout
              : NetworkErrorType.unknown,
          failure.toString(),
        );
      } else {
        error = GrpcWebInspector.errorFor(details);
      }
      return NetworkLogEntry(
        id: _id,
        method: 'GRPC',
        url: _capture.url(_url),
        timestamp: _startedAt,
        duration: duration,
        protocol: NetworkProtocol.grpc,
        connectionId: _streaming ? _id : null,
        requestHeaders: _capture.headers(_metadata),
        responseHeaders: _capture.headers(trailers),
        requestBody: _firstSent,
        responseBody: _firstReceived,
        error: error,
        details: [details],
      );
    });
  }
}
