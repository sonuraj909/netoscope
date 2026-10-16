import 'dart:async';
import 'dart:convert';

import '../../core/entities/graphql_details.dart';
import '../../core/entities/network_event_kind.dart';
import '../../core/entities/protocol_details.dart';
import '../observe_stream.dart';
import 'connection_recorder.dart';

/// Records a WebSocket connection.
///
/// Works with any WebSocket implementation that exposes a `Stream` of
/// incoming messages and a `StreamSink` for outgoing ones, such as
/// `package:web_socket_channel` or `dart:io`'s `WebSocket`, without
/// depending on them:
///
/// ```dart
/// final channel = WebSocketChannel.connect(url);
/// final socket = netoscope.webSocket(url);
/// await channel.ready;
/// socket.opened(subprotocol: channel.protocol);
/// final messages = socket.observeIncoming(
///   channel.stream,
///   closeCode: () => channel.closeCode,
///   closeReason: () => channel.closeReason,
/// );
/// final sink = socket.observeOutgoing(channel.sink);
/// ```
///
/// GraphQL operations sent with the `graphql-transport-ws` or
/// `subscriptions-transport-ws` protocols are recognized automatically.
class WebSocketRecorder extends ConnectionRecorder {
  /// Creates a recorder. Use `Netoscope.webSocket` instead.
  WebSocketRecorder(
    super.capture, {
    required super.url,
    super.requestHeaders,
    super.ignoreMessage,
  }) : super(protocol: NetworkProtocol.webSocket, label: 'WS');

  /// Records the connection as established.
  void connected({
    String? subprotocol,
    Map<String, String> responseHeaders = const {},
  }) =>
      opened(
        statusCode: 101,
        responseHeaders: responseHeaders,
        details: [WebSocketDetails(subprotocol: subprotocol)],
      );

  /// Records a close with an optional close [code] and [reason].
  void disconnected({int? code, String? reason, String? closedBy}) => closed(
        closedBy: closedBy,
        details: [WebSocketDetails(closeCode: code, closeReason: reason)],
      );

  /// Records an outgoing message.
  void sent(Object? data) => _frame(MessageDirection.outgoing, data);

  /// Records an incoming message.
  void received(Object? data) => _frame(MessageDirection.incoming, data);

  /// Returns [source] unchanged in content, recording each incoming message,
  /// the close (with [closeCode] and [closeReason] read when the stream
  /// ends) and errors. Pause, resume and cancel reach [source] unchanged.
  Stream<T> observeIncoming<T>(
    Stream<T> source, {
    int? Function()? closeCode,
    String? Function()? closeReason,
  }) {
    if (!isActive) return source;
    return observeStream(
      source,
      onData: received,
      onError: failed,
      onDone: () => disconnected(
        code: closeCode?.call(),
        reason: closeReason?.call(),
      ),
      onCancel: () => disconnected(
        code: closeCode?.call(),
        reason: closeReason?.call(),
        closedBy: 'client',
      ),
    );
  }

  /// Wraps [sink] so every message added to it is recorded before being
  /// forwarded unchanged.
  StreamSink<T> observeOutgoing<T>(StreamSink<T> sink) =>
      isActive ? _ObservedSink<T>(sink, sent) : sink;

  void _frame(MessageDirection direction, Object? data) {
    if (!isActive) return;
    final graphQL = _graphQL(data);
    message(
      direction,
      data,
      details: [
        WebSocketDetails(
          frameType: data is String
              ? WebSocketFrameType.text
              : WebSocketFrameType.binary,
        ),
        if (graphQL != null) graphQL,
      ],
    );
  }

  static const _operationTypes = {'subscribe', 'start'};
  static const _resultTypes = {'next', 'data', 'error'};

  GraphQLDetails? _graphQL(Object? data) {
    if (!capture.config.detectGraphQL || data is! String) return null;
    if (data.length > 256 * 1024 || !data.trimLeft().startsWith('{')) {
      return null;
    }
    try {
      final message = jsonDecode(data);
      if (message is! Map) return null;
      final type = message['type'];
      final payload = message['payload'];
      if (_operationTypes.contains(type)) {
        final operation = capture.graphQL.operationFrom(payload);
        return operation == null
            ? null
            : GraphQLDetails(operations: [operation]);
      }
      if (_resultTypes.contains(type)) {
        final response = type == 'error' ? {'errors': payload} : payload;
        final errors = capture.graphQL.errorsFrom(response);
        final hasData = response is Map && response['data'] != null;
        if (errors.isEmpty && !hasData) return null;
        return GraphQLDetails(
          operations: const [],
          errors: errors,
          hasData: hasData,
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class _ObservedSink<T> implements StreamSink<T> {
  _ObservedSink(this._inner, this._onAdd);

  final StreamSink<T> _inner;
  final void Function(Object? data) _onAdd;

  void _report(T data) {
    try {
      _onAdd(data);
    } catch (_) {
      // Observation must never affect sending.
    }
  }

  @override
  void add(T data) {
    _report(data);
    _inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<T> stream) => _inner.addStream(
        stream.map((data) {
          _report(data);
          return data;
        }),
      );

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> get done => _inner.done;
}
