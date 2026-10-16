import 'dart:convert';

/// One parsed Server-Sent Event.
class SseEvent {
  /// Creates an event.
  const SseEvent({
    required this.data,
    this.type = 'message',
    this.id,
    this.retry,
    this.isTruncated = false,
  });

  /// The event type (`event:` field), `message` by default.
  final String type;

  /// The `data:` lines joined with newlines.
  final String data;

  /// The last event ID (`id:` field) at dispatch time.
  final String? id;

  /// The reconnection time (`retry:` field), if sent with this event.
  final Duration? retry;

  /// Whether [data] was cut at the parser's limit.
  final bool isTruncated;
}

/// An incremental `text/event-stream` parser following the WHATWG rules.
///
/// Feed raw bytes with [add]; complete events are passed to the callback.
/// Data for a single event is bounded by [maxEventSize] characters.
class SseParser {
  /// Creates a parser reporting events to [onEvent].
  SseParser(this.onEvent, {this.maxEventSize = 1024 * 1024}) {
    _bytes = const Utf8Decoder(allowMalformed: true).startChunkedConversion(
      const LineSplitter().startChunkedConversion(_LineSink(_line)),
    );
  }

  /// Receives each complete event.
  final void Function(SseEvent event) onEvent;

  /// The maximum number of data characters kept per event.
  final int maxEventSize;

  late final ByteConversionSink _bytes;
  final StringBuffer _data = StringBuffer();
  String? _type;
  String? _lastId;
  Duration? _retry;
  bool _hasData = false;
  bool _truncated = false;

  /// Adds a chunk of the stream.
  void add(List<int> chunk) => _bytes.add(chunk);

  /// Flushes a trailing event that was not followed by a blank line.
  void close() => _bytes.close();

  void _line(String line) {
    if (line.isEmpty) {
      _dispatch();
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        _type = value;
      case 'data':
        if (_hasData) _append('\n');
        _append(value);
        _hasData = true;
      case 'id':
        if (!value.contains('\u0000')) _lastId = value;
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null && ms >= 0) _retry = Duration(milliseconds: ms);
    }
  }

  void _append(String text) {
    final room = maxEventSize - _data.length;
    if (room <= 0) {
      _truncated = true;
      return;
    }
    if (text.length > room) {
      _data.write(text.substring(0, room));
      _truncated = true;
    } else {
      _data.write(text);
    }
  }

  void _dispatch() {
    if (_hasData) {
      onEvent(
        SseEvent(
          data: _data.toString(),
          type: _type == null || _type!.isEmpty ? 'message' : _type!,
          id: _lastId,
          retry: _retry,
          isTruncated: _truncated,
        ),
      );
    }
    _data.clear();
    _type = null;
    _retry = null;
    _hasData = false;
    _truncated = false;
  }
}

class _LineSink implements Sink<String> {
  _LineSink(this._onLine);

  final void Function(String line) _onLine;

  @override
  void add(String line) => _onLine(line);

  @override
  void close() => _onLine('');
}
