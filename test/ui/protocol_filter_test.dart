import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/ui/network_log_filter.dart';

import '../support/protocol_fixtures.dart';

void main() {
  final entries = protocolFixtures();

  List<String> ids(NetworkLogFilter filter) => [
        for (final e in filter.apply(
          entries,
          slowThreshold: const Duration(seconds: 1),
          now: fixtureNow,
        ))
          e.id,
      ];

  test('filters by protocol', () {
    expect(
      ids(const NetworkLogFilter(protocols: {NetworkProtocol.webSocket})),
      ['ws-open', 'ws-out'],
    );
    expect(
      ids(const NetworkLogFilter(
        protocols: {NetworkProtocol.sse, NetworkProtocol.mqtt},
      )),
      ['sse', 'mqtt'],
    );
  });

  test('filters by message direction', () {
    expect(
      ids(const NetworkLogFilter(direction: MessageDirection.incoming)),
      ['sse', 'mqtt'],
    );
  });

  test('filters by SSE event type and payload format', () {
    expect(ids(const NetworkLogFilter(sseEventType: 'price')), ['sse']);
    expect(ids(const NetworkLogFilter(payloadFormat: PayloadFormat.xml)),
        ['rest']);
  });

  test('filters by time range', () {
    expect(
      ids(const NetworkLogFilter(timeRange: TimeRangeFilter.lastMinute)),
      ['gql', 'ws-open', 'ws-out', 'sse', 'grpc', 'mqtt'],
    );
    expect(
      ids(const NetworkLogFilter(timeRange: TimeRangeFilter.lastFifteenMinutes))
          .contains('rest'),
      isFalse,
    );
  });

  test('filters GraphQL calls and GraphQL errors', () {
    expect(ids(const NetworkLogFilter(onlyGraphQL: true)), ['gql']);
    expect(ids(const NetworkLogFilter(onlyGraphQLErrors: true)), ['gql']);
  });

  test('filters by connection', () {
    expect(
        ids(const NetworkLogFilter(connectionId: 'c1')), ['ws-open', 'ws-out']);
  });

  test('search covers operation names, event types, topics and methods', () {
    expect(ids(const NetworkLogFilter(query: 'getviewer')), ['gql']);
    expect(ids(const NetworkLogFilter(query: 'price')), ['sse']);
    expect(ids(const NetworkLogFilter(query: 'devices/1')), ['mqtt']);
    expect(ids(const NetworkLogFilter(query: 'Users/GetUser')), ['grpc']);
  });

  test('"Failed" means failed outcomes, not missing HTTP status', () {
    expect(ids(const NetworkLogFilter(status: StatusFilter.failed)), ['grpc']);
  });

  test('counts active filters', () {
    const filter = NetworkLogFilter(
      protocols: {NetworkProtocol.sse},
      timeRange: TimeRangeFilter.lastHour,
      onlyGraphQLErrors: true,
    );
    expect(filter.activeCount, 3);
    expect(filter.copyWith(clearConnection: true).connectionId, isNull);
  });
}
