import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import '../support/protocol_fixtures.dart';

class _UpperViewer extends PayloadViewer {
  const _UpperViewer();

  @override
  bool canView(NetworkLogBody body) => body.format == PayloadFormat.xml;

  @override
  Widget build(BuildContext context, NetworkLogBody body) =>
      Text('CUSTOM ${body.content.toUpperCase()}');
}

void main() {
  late Netoscope netoscope;

  setUp(() {
    final store = InMemoryNetworkLogStore();
    for (final entry in protocolFixtures()) {
      store.add(entry);
    }
    netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    List<PayloadViewer> viewers = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkInspector(netoscope: netoscope, payloadViewers: viewers),
      ),
    );
  }

  testWidgets('shows protocol-aware rows', (tester) async {
    await pump(tester);

    expect(find.text('WS ↑'), findsOneWidget);
    expect(find.text('WS open'), findsOneWidget);
    expect(find.text('SSE ↓'), findsOneWidget);
    expect(find.text('event: price'), findsOneWidget);
    expect(find.text('/graphql · query GetViewer'), findsOneWidget);
    expect(find.text('GQL ERR'), findsOneWidget);
    expect(find.text('gRPC-Web'), findsOneWidget);
    expect(find.text('NOT_FOUND'), findsOneWidget);
    expect(find.text('devices/1/state'), findsOneWidget);
  });

  testWidgets('the filter sheet narrows by protocol and GraphQL errors',
      (tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'WebSocket'));
    await tester.pumpAndSettle();
    expect(find.text('Filters (1)'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // Dismiss the sheet.
    await tester.pumpAndSettle();
    expect(find.text('WS ↑'), findsOneWidget);
    expect(find.text('SSE ↓'), findsNothing);
    expect(find.text('/users'), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, 'Filters (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.tap(find.widgetWithText(FilterChip, 'With GraphQL errors'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('/graphql · query GetViewer'), findsOneWidget);
    expect(find.text('WS ↑'), findsNothing);
  });

  testWidgets('the GraphQL tab shows operations and errors', (tester) async {
    await pump(tester);

    await tester.tap(find.text('/graphql · query GetViewer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GraphQL'));
    await tester.pumpAndSettle();

    expect(find.text('query GetViewer'), findsOneWidget);
    expect(find.text('query GetViewer { viewer { id } }'), findsOneWidget);
    expect(find.text('Not allowed'), findsOneWidget);
    expect(find.text('Path: viewer.id'), findsOneWidget);
    expect(find.text('Code: FORBIDDEN'), findsOneWidget);
    expect(find.text('partial (with errors)'), findsOneWidget);
  });

  testWidgets('message details link to the connection', (tester) async {
    await pump(tester);

    await tester.tap(find.text('WS ↑'));
    await tester.pumpAndSettle();
    expect(find.text('Payload'), findsOneWidget);

    await tester.tap(find.text('Payload'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"subscribe": "prices"'), findsOneWidget);

    await tester.tap(find.byTooltip('View connection events'));
    await tester.pumpAndSettle();
    expect(find.text('Connection events'), findsOneWidget);
    expect(find.text('WS open'), findsOneWidget);
    expect(find.text('SSE ↓'), findsNothing);
  });

  testWidgets('custom payload viewers take precedence', (tester) async {
    await pump(tester, viewers: const [_UpperViewer()]);

    await tester.tap(find.text('/users'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    expect(find.text('CUSTOM <USERS><USER>ADA</USER></USERS>'), findsOneWidget);
  });

  testWidgets('long bodies render lazily', (tester) async {
    final lines = [for (var i = 0; i < 3000; i++) 'line $i'].join('\n');
    final store = InMemoryNetworkLogStore()
      ..add(
        NetworkLogEntry(
          id: 'big',
          method: 'GET',
          url: Uri.parse('https://api.dev/big'),
          timestamp: fixtureNow,
          statusCode: 200,
          responseBody:
              NetworkLogBody(kind: NetworkBodyKind.text, content: lines),
        ),
      );
    netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    await pump(tester);

    await tester.tap(find.text('/big'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('netoscope-lazy-body')), findsOneWidget);
    expect(find.text('line 0'), findsOneWidget);
    expect(find.text('line 2999'), findsNothing, reason: 'not built yet');
  });
}
