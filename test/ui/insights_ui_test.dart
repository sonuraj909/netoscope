import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

final _t0 = DateTime.now().subtract(const Duration(minutes: 1));

NetworkLogEntry _call(
  String id,
  String path, {
  int ms = 0,
  String method = 'GET',
  int? status = 200,
  int duration = 120,
  List<String> tags = const [],
}) =>
    NetworkLogEntry(
      id: id,
      method: method,
      url: Uri.parse('https://api.dev$path'),
      timestamp: _t0.add(Duration(milliseconds: ms)),
      statusCode: status,
      duration: Duration(milliseconds: duration),
      responseSize: 1200,
      tags: tags,
    );

void main() {
  late Netoscope netoscope;
  String? clipboard;
  NetoscopeExport? shared;

  setUp(() {
    clipboard = null;
    shared = null;
    final store = InMemoryNetworkLogStore(maxEntries: 50);
    for (final entry in [
      _call('list', '/users', tags: ['login-flow']),
      for (var i = 1; i <= 6; i++) _call('u$i', '/users/$i', ms: 40 * i),
      _call('pay', '/pay', method: 'POST', status: 503, ms: 400, duration: 900),
      _call('me1', '/me', ms: 500),
      _call('me2', '/me', ms: 520),
    ]) {
      store.add(entry);
    }
    netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        slowRequestThreshold: Duration(milliseconds: 800),
      ),
      exportHandler: (export) async => shared = export,
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(home: NetworkInspector(netoscope: netoscope)),
    );
  }

  testWidgets('rows show N+1, duplicate badges and tags', (tester) async {
    await pump(tester);
    expect(find.text('N+1'), findsNWidgets(6));
    expect(find.text('DUP'), findsNWidgets(2));
    expect(find.textContaining('#login-flow'), findsOneWidget);
  });

  testWidgets('search syntax and its help sheet', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Search syntax'));
    await tester.pumpAndSettle();
    expect(find.text('Search syntax'), findsWidgets);
    await tester.tap(find.text('is:n+1'));
    await tester.pumpAndSettle();
    expect(find.text('N+1'), findsNWidgets(6));
    expect(find.text('/pay'), findsNothing);

    await tester.enterText(find.byType(TextField), 'method:POST status:5xx');
    await tester.pump();
    expect(find.text('/pay'), findsOneWidget);
    expect(find.text('/me'), findsNothing);
  });

  testWidgets('statistics summarize and link to redundant calls',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Statistics'));
    await tester.pumpAndSettle();
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('10'), findsWidgets);
    expect(find.text('90%'), findsOneWidget, reason: '9 of 10 succeeded');
    expect(find.text('Failed (no response)'), findsNothing);
    expect(find.text('5xx'), findsOneWidget);
    expect(find.textContaining('Possible N+1 · 6 calls'), findsOneWidget);
    expect(find.textContaining('Duplicate requests · 2 calls'), findsOneWidget);

    await tester.tap(find.textContaining('Possible N+1 · 6 calls'));
    await tester.pumpAndSettle();
    expect(find.text('6 selected calls'), findsOneWidget);
    expect(find.text('/users/3'), findsOneWidget);
    expect(find.text('/me'), findsNothing);
  });

  testWidgets('the timeline lays out calls and opens one on tap',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Timeline'));
    await tester.pumpAndSettle();
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('10 events · 1.30 s'), findsOneWidget);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    await tester.tap(find.byTooltip('Fit'));
    await tester.pump();

    // The first row (oldest call) is /users.
    final bars = find.byKey(const ValueKey('netoscope-timeline-bars'));
    await tester.tapAt(tester.getTopLeft(bars) + const Offset(40, 10));
    await tester.pumpAndSettle();
    expect(find.text('https://api.dev/users'), findsOneWidget);
    expect(find.text('#login-flow'), findsOneWidget);
  });

  testWidgets('the detail explains an N+1 burst', (tester) async {
    await pump(tester);

    await tester.tap(find.text('/users/2'));
    await tester.pumpAndSettle();
    expect(find.text('Possible N+1: 6 calls in 200 ms'), findsOneWidget);
    expect(find.text('GET api.dev/users/{id}'), findsOneWidget);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('6 selected calls'), findsOneWidget);
  });

  testWidgets('HAR copy and share from the menu', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy as HAR'));
    await tester.pumpAndSettle();
    final har = jsonDecode(clipboard!) as Map<String, Object?>;
    expect(((har['log']! as Map)['entries']! as List), hasLength(10));

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share HAR…'));
    await tester.pumpAndSettle();
    expect(shared!.fileName, endsWith('.har'));
    expect(shared!.mimeType, 'application/json');
  });

  testWidgets('the filter sheet filters by tag and redundancy', (tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(ActionChip, 'Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Duplicates (2)'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('/me'), findsNWidgets(2));
    expect(find.text('/users'), findsNothing);
  });
}
