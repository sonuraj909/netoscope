import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

final _t0 = DateTime.utc(2026, 1, 1, 12);

NetworkLogEntry _call(
  String id,
  String url, {
  int ms = 0,
  String method = 'GET',
  int? status = 200,
  int duration = 100,
  int? size,
  String? body,
}) =>
    NetworkLogEntry(
      id: id,
      method: method,
      url: Uri.parse(url),
      timestamp: _t0.add(Duration(milliseconds: ms)),
      statusCode: status,
      duration: Duration(milliseconds: duration),
      responseSize: size,
      requestBody: body == null
          ? null
          : NetworkLogBody(kind: NetworkBodyKind.json, content: body),
    );

void main() {
  const analyzer = TrafficAnalyzer();

  group('endpoint patterns', () {
    test('ID-like segments become {id}; query values are dropped', () {
      String pattern(String url) =>
          TrafficAnalyzer.endpointPattern(_call('x', url));
      expect(pattern('https://a.dev/users/42/posts'),
          'GET a.dev/users/{id}/posts');
      expect(
        pattern('https://a.dev/o/550e8400-e29b-41d4-a716-446655440000'),
        'GET a.dev/o/{id}',
      );
      expect(pattern('https://a.dev/i/5f1d7c3e9a2b4c6d8e0f1a2b'),
          'GET a.dev/i/{id}');
      expect(pattern('https://a.dev/items?id=3&lang=en'),
          'GET a.dev/items?id&lang');
      expect(pattern('https://a.dev/v2/users/me'), 'GET a.dev/v2/users/me');
    });
  });

  test('finds identical requests within the window', () {
    final insights = analyzer.analyze([
      _call('1', 'https://a.dev/me', ms: 0),
      _call('2', 'https://a.dev/me', ms: 300),
      _call('3', 'https://a.dev/me', ms: 5000), // separate burst, alone
      _call('4', 'https://a.dev/other', ms: 100),
      _call('5', 'https://a.dev/save', method: 'POST', body: '{"a":1}', ms: 0),
      _call('6', 'https://a.dev/save', method: 'POST', body: '{"a":2}', ms: 10),
    ]);

    expect(insights.duplicates, hasLength(1));
    expect(insights.duplicates.single.pattern, 'GET https://a.dev/me');
    expect(insights.duplicates.single.count, 2);
    expect(insights.duplicateIds, {'1', '2'});
  });

  test('finds N+1 bursts of one pattern with different IDs', () {
    final insights = analyzer.analyze([
      _call('list', 'https://a.dev/users', ms: 0),
      for (var i = 1; i <= 6; i++)
        _call('u$i', 'https://a.dev/users/$i', ms: 50 + i * 40),
      for (var i = 1; i <= 3; i++)
        _call('p$i', 'https://a.dev/posts/$i', ms: 50 + i * 40),
    ]);

    expect(insights.nPlusOne, hasLength(1));
    final group = insights.nPlusOne.single;
    expect(group.pattern, 'GET a.dev/users/{id}');
    expect(group.count, 6);
    expect(group.span, const Duration(milliseconds: 200));
    expect(insights.nPlusOneIds, {for (var i = 1; i <= 6; i++) 'u$i'});
    expect(insights.duplicates, isEmpty);
  });

  test('repeating the same URL is not N+1', () {
    final insights = analyzer.analyze([
      for (var i = 0; i < 6; i++)
        _call('$i', 'https://a.dev/users/1', ms: i * 10),
    ]);
    expect(insights.nPlusOne, isEmpty);
    expect(insights.duplicates.single.count, 6);
  });

  test('statistics', () {
    final entries = [
      _call('1', 'https://a.dev/users/1', duration: 100, size: 1000),
      _call('2', 'https://a.dev/users/2', duration: 300, size: 3000),
      _call('3', 'https://a.dev/pay',
          method: 'POST', status: 500, duration: 900),
      _call('4', 'https://b.dev/x', status: null, duration: 50),
      NetworkLogEntry(
        id: 'ws',
        method: 'WS',
        url: Uri.parse('wss://rt.dev'),
        timestamp: _t0,
        protocol: NetworkProtocol.webSocket,
        kind: NetworkEventKind.message,
        direction: MessageDirection.incoming,
        responseSize: 24,
      ),
    ];
    final stats = TrafficStatistics.from(
      entries,
      slowThreshold: const Duration(milliseconds: 500),
    );

    expect(stats.totalEvents, 5);
    expect(stats.exchanges, 4);
    expect(stats.successes, 2);
    expect(stats.httpErrors, 1);
    expect(stats.failures, 1);
    expect(stats.successRate, 0.5);
    expect(stats.slow, 1);
    expect(stats.bytesReceived, 4024);
    expect(stats.averageDuration,
        const Duration(milliseconds: 337, microseconds: 500));
    expect(stats.medianDuration, const Duration(milliseconds: 300));
    expect(stats.maxDuration, const Duration(milliseconds: 900));
    expect(stats.byStatusClass, {'2xx': 2, '5xx': 1, 'Failed': 1});
    expect(stats.byMethod, {'GET': 3, 'POST': 1});
    expect(stats.byProtocol, {'HTTP': 4, 'WebSocket': 1});
    expect(stats.byHost.keys.first, 'a.dev');
    expect(stats.busiestEndpoints.first.pattern, 'GET a.dev/users/{id}');
    expect(stats.busiestEndpoints.first.calls, 2);
    expect(stats.slowestEndpoints.first.pattern, 'POST a.dev/pay');
  });
}
