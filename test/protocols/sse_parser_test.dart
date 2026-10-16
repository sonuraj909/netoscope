import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/src/protocols/sse/sse_parser.dart';

void main() {
  List<SseEvent> parse(List<List<int>> chunks, {int max = 1024}) {
    final events = <SseEvent>[];
    final parser = SseParser(events.add, maxEventSize: max);
    chunks.forEach(parser.add);
    parser.close();
    return events;
  }

  test('parses types, multi-line data, ids, retry and comments', () {
    final events = parse([
      utf8.encode(
        ': keep-alive\n'
        'data: first\n\n'
        'event: update\nid: 7\nretry: 1500\ndata: line 1\ndata: line 2\n\n'
        'data:no-space\n\n',
      ),
    ]);
    expect(events.map((e) => e.type), ['message', 'update', 'message']);
    expect(events[1].data, 'line 1\nline 2');
    expect(events[1].id, '7');
    expect(events[1].retry, const Duration(milliseconds: 1500));
    expect(events[2].id, '7', reason: 'the last event ID persists');
    expect(events[2].retry, isNull);
    expect(events[2].data, 'no-space');
  });

  test('handles chunk boundaries inside lines and UTF-8 sequences', () {
    final bytes = utf8.encode('data: héllo\r\n\r\n');
    final events = parse([
      for (final b in bytes) [b]
    ]);
    expect(events.single.data, 'héllo');
  });

  test('ignores events without data and flushes a trailing event', () {
    final events = parse([utf8.encode('event: ping\n\ndata: last')]);
    expect(events.single.data, 'last');
  });

  test('bounds the data kept per event', () {
    final events = parse([utf8.encode('data: ${'x' * 50}\n\n')], max: 10);
    expect(events.single.data, 'x' * 10);
    expect(events.single.isTruncated, isTrue);
  });
}
