import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryNetworkLogStore store;
  late Netoscope netoscope;

  setUp(() {
    store = InMemoryNetworkLogStore()
      ..add(makeEntry(id: 'users', url: 'https://api.dev/users'))
      ..add(
        makeEntry(
          id: 'login',
          method: 'POST',
          url: 'https://api.dev/login',
          statusCode: 401,
          requestHeaders: {'Authorization': '***'},
          responseBody: const NetworkLogBody(
            kind: NetworkBodyKind.json,
            content: '{"error":"invalid","token":"***"}',
          ),
        ),
      )
      ..add(
        makeEntry(
          id: 'reports',
          url: 'https://api.dev/reports',
          statusCode: null,
          duration: const Duration(seconds: 5),
          error: const NetworkLogError(
            type: NetworkErrorType.timeout,
            message: 'Receive timeout',
          ),
        ),
      );
    netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
  });

  Future<void> pumpInspector(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NetworkInspector(netoscope: netoscope)),
    );
  }

  testWidgets('lists calls and updates when new ones arrive', (tester) async {
    await pumpInspector(tester);

    expect(find.text('/users'), findsOneWidget);
    expect(find.text('/login'), findsOneWidget);
    expect(find.text('401'), findsOneWidget);
    expect(find.text('TIMEOUT'), findsOneWidget);

    store.add(makeEntry(id: 'new', url: 'https://api.dev/fresh'));
    await tester.pump();
    expect(find.text('/fresh'), findsOneWidget);
  });

  testWidgets('searches by URL', (tester) async {
    await pumpInspector(tester);

    await tester.enterText(find.byType(TextField), 'log');
    await tester.pump();

    expect(find.text('/login'), findsOneWidget);
    expect(find.text('/users'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing-matches');
    await tester.pump();
    expect(find.text('No requests match the current filters.'), findsOneWidget);
  });

  testWidgets('filters by status, method and slowness', (tester) async {
    await pumpInspector(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '4xx'));
    await tester.pump();
    expect(find.text('/login'), findsOneWidget);
    expect(find.text('/users'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.tap(find.widgetWithText(FilterChip, 'Slow'));
    await tester.pump();
    expect(find.text('/reports'), findsOneWidget);
    expect(find.text('/login'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'Slow'));
    await tester.pump();
    await tester.dragUntilVisible(
      find.widgetWithText(FilterChip, 'POST'),
      find.byType(ListView).first,
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'POST'));
    await tester.pump();
    expect(find.text('/login'), findsOneWidget);
    expect(find.text('/users'), findsNothing);
  });

  testWidgets('shows request details', (tester) async {
    await pumpInspector(tester);

    await tester.tap(find.text('/login'));
    await tester.pumpAndSettle();
    expect(find.text('https://api.dev/login'), findsOneWidget);

    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    expect(find.text('Authorization'), findsOneWidget);
    expect(find.text('***'), findsOneWidget);

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    expect(
      find.text('{\n  "error": "invalid",\n  "token": "***"\n}'),
      findsOneWidget,
    );
  });

  testWidgets('shows error details for failed calls', (tester) async {
    await pumpInspector(tester);

    await tester.tap(find.text('/reports'));
    await tester.pumpAndSettle();
    expect(find.text('Receive timeout'), findsOneWidget);

    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();
    expect(find.text('No response was received.'), findsOneWidget);
  });

  testWidgets('clears history after confirmation', (tester) async {
    await pumpInspector(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(netoscope.logs, hasLength(3));

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(netoscope.logs, isEmpty);
    expect(find.text('No requests recorded yet.'), findsOneWidget);
  });

  testWidgets('exports history as JSON to the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpInspector(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy all as JSON'));
    await tester.pumpAndSettle();

    final json = jsonDecode(copied!) as Map<String, Object?>;
    expect(json['count'], 3);
    expect(find.text('Copied 3 requests as JSON'), findsOneWidget);
  });

  group('availability', () {
    testWidgets('button is hidden when the inspector is turned off',
        (tester) async {
      final hidden = Netoscope(
        config: const NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
          showInspector: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(body: NetworkInspectorButton(netoscope: hidden))),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('openInspector does nothing when logging is disabled',
        (tester) async {
      final disabled =
          Netoscope(config: const NetworkLoggerConfig(enabled: false));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => disabled.openInspector(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkInspector), findsNothing);
    });

    testWidgets('overlay button in MaterialApp.builder opens the inspector',
        (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => NetworkInspectorOverlay(
            netoscope: netoscope,
            navigatorKey: navigatorKey,
            child: child!,
          ),
          home: const Scaffold(body: Text('home')),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(NetworkInspector), findsOneWidget);
      // The floating button hides while the inspector is open…
      expect(find.byType(FloatingActionButton), findsNothing);

      // …and comes back when it closes.
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}
