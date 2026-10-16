import '../../core/entities/network_event_kind.dart';
import '../../core/entities/protocol_details.dart';
import '../../protocols/sse/sse_parser.dart';
import '../observe_stream.dart';
import 'connection_recorder.dart';

/// Records a Server-Sent Events connection.
///
/// `package:http` clients from `Netoscope.httpClient` record
/// `text/event-stream` responses automatically. For other clients, wrap the
/// raw byte stream:
///
/// ```dart
/// final response = await dio.get<ResponseBody>(url,
///     options: Options(responseType: ResponseType.stream));
/// final events = netoscope.serverSentEvents(Uri.parse(url));
/// events.connected(statusCode: response.statusCode);
/// final bytes = events.observeBytes(response.data!.stream);
/// ```
class SseRecorder extends ConnectionRecorder {
  /// Creates a recorder. Use `Netoscope.serverSentEvents` instead.
  SseRecorder(
    super.capture, {
    required super.url,
    super.requestHeaders,
    super.ignoreMessage,
  }) : super(protocol: NetworkProtocol.sse, label: 'SSE');

  /// Records the connection as established.
  void connected({
    int? statusCode,
    Map<String, String> responseHeaders = const {},
  }) =>
      opened(statusCode: statusCode, responseHeaders: responseHeaders);

  /// Records one event.
  void event({
    required String data,
    String type = 'message',
    String? id,
    Duration? retry,
  }) =>
      message(
        MessageDirection.incoming,
        data,
        details: [SseDetails(eventType: type, eventId: id, retry: retry)],
      );

  /// Returns [source] unchanged, parsing and recording each event as the
  /// caller reads it. The end of the stream is recorded as a close, errors
  /// as failures and cancellation as a client-side close. Data of a single
  /// event is parsed up to 1 MiB.
  Stream<T> observeBytes<T extends List<int>>(Stream<T> source) {
    if (!isActive) return source;
    final parser = SseParser(
      (e) => event(data: e.data, type: e.type, id: e.id, retry: e.retry),
    );
    return observeStream(
      source,
      onData: parser.add,
      onError: failed,
      onDone: () {
        parser.close();
        closed(closedBy: 'server');
      },
      onCancel: () => closed(closedBy: 'client'),
    );
  }
}
