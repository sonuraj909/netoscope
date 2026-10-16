import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/ui/network_log_filter.dart';
import 'package:netoscope/src/ui/search_query.dart';

NetworkLogEntry _e(
  String id,
  String url, {
  String method = 'GET',
  int? status = 200,
  int duration = 100,
  int? size,
  List<String> tags = const [],
  Map<String, String> headers = const {},
  String? body,
  List<ProtocolDetails> details = const [],
  NetworkProtocol protocol = NetworkProtocol.http,
}) =>
    NetworkLogEntry(
      id: id,
      method: method,
      url: Uri.parse(url),
      timestamp: DateTime.utc(2026, 1, 1, 12)
          .add(Duration(milliseconds: int.parse(id) * 10)),
      statusCode: status,
      duration: Duration(milliseconds: duration),
      responseSize: size,
      tags: tags,
      requestHeaders: headers,
      protocol: protocol,
      details: details,
      responseBody: body == null
          ? null
          : NetworkLogBody(kind: NetworkBodyKind.text, content: body),
    );

void main() {
  final entries = [
    _e('1', 'https://api.dev/users',
        duration: 80, size: 2048, tags: ['login-flow']),
    _e('2', 'https://api.dev/login',
        method: 'POST',
        status: 401,
        duration: 600,
        headers: {'Authorization': '***'},
        body: 'invalid credentials'),
    _e('3', 'https://cdn.dev/logo.png', duration: 1500, size: 300000),
    _e('4', 'https://api.dev/pay', method: 'POST', status: 503, duration: 30),
    _e('5', 'https://api.dev/graphql', method: 'POST', details: [
      GraphQLDetails(
        operations: const [
          GraphQLOperation(name: 'GetUser', type: GraphQLOperationType.query)
        ],
        errors: [GraphQLError(message: 'denied')],
      ),
    ]),
    _e('6', 'wss://rt.dev/socket',
        method: 'WS', status: null, protocol: NetworkProtocol.webSocket),
    _e('7', 'https://api.dev/users', duration: 90),
  ];
  final context = SearchContext(
    slowThreshold: const Duration(seconds: 1),
    insights: const TrafficAnalyzer().analyze(entries),
  );

  List<String> search(String query) {
    final parsed = SearchQuery.parse(query);
    return [
      for (final e in entries)
        if (parsed.matches(e, context)) e.id
    ];
  }

  test('free text matches the URL and tags', () {
    expect(search('logo'), ['3']);
    expect(search('#login-flow'), ['1']);
    expect(search(''), hasLength(7));
  });

  test('method and status', () {
    expect(search('method:post'), ['2', '4', '5']);
    expect(search('method:get,ws'), ['1', '3', '6', '7']);
    expect(search('status:4xx'), ['2']);
    expect(search('status:>=500'), ['4']);
    expect(search('status:400-503'), ['2', '4']);
    // A WebSocket event without an error is not a failure.
    expect(search('status:error'), ['2', '4']);
    expect(search('status:200'), ['1', '3', '5', '7']);
  });

  test('host, path, duration and size with units', () {
    expect(search('host:cdn'), ['3']);
    expect(search('path:/users'), ['1', '7']);
    expect(search('duration:>500'), ['2', '3']);
    expect(search('duration:>=1s'), ['3']);
    expect(search('duration:50-100ms'), ['1', '5', '6', '7']);
    expect(search('size:>100kb'), ['3']);
    expect(search('size:<1kb'), <String>[]);
  });

  test('protocol, tags, is:, op:, header: and body:', () {
    expect(search('protocol:ws'), ['6']);
    expect(search('tag:login-flow'), ['1']);
    expect(search('is:slow'), ['3']);
    expect(search('is:graphql'), ['5']);
    expect(search('is:error'), ['2', '4', '5']);
    expect(search('is:duplicate'), ['1', '7']);
    expect(search('op:getuser'), ['5']);
    expect(search('header:authorization'), ['2']);
    expect(search('body:"invalid credentials"'), ['2']);
  });

  test('terms combine; negation excludes', () {
    expect(search('method:POST -status:5xx'), ['2', '5']);
    expect(search('host:api.dev !method:get'), ['2', '4', '5']);
    expect(search('method:POST status:4xx login'), ['2']);
  });

  test('unknown keys fall back to free text', () {
    final parsed = SearchQuery.parse('foo:bar');
    expect(parsed.unknownKeys, ['foo']);
    expect(parsed.matches(entries.first, context), isFalse);
  });

  test('NetworkLogFilter uses the syntax and insight filters', () {
    final insights = const TrafficAnalyzer().analyze([
      ...entries,
      _e('8', 'https://api.dev/users', duration: 90),
    ]);
    final filter = const NetworkLogFilter(query: 'path:/users')
        .copyWith(onlyDuplicates: true);
    expect(
      filter
          .apply(
            entries,
            slowThreshold: const Duration(seconds: 1),
            insights: insights,
          )
          .map((e) => e.id),
      ['1', '7'],
    );
    expect(const NetworkLogFilter(tag: 'login-flow').activeCount, 1);
  });
}
