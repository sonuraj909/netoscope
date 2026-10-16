import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope_example/main.dart';

void main() {
  testWidgets('sends a request and shows it in the inspector', (tester) async {
    await tester.pumpWidget(const NetoscopeExampleApp());

    await tester.tap(find.text('GET /users'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('GET /users: done'), findsOneWidget);
    expect(find.text('1 requests recorded'), findsOneWidget);

    await tester.tap(find.byTooltip('Open inspector'));
    await tester.pumpAndSettle();
    expect(find.byType(NetworkInspector), findsOneWidget);
    expect(find.text('/users'), findsOneWidget);
  });

  testWidgets('redacts credentials from the login call', (tester) async {
    await tester.pumpWidget(const NetoscopeExampleApp());

    await tester.tap(find.text('POST /auth/login (redacted)'));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Open inspector'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/auth/login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();

    expect(find.textContaining('hunter2'), findsNothing);
    expect(find.textContaining('ada@example.com'), findsNothing);
    expect(find.textContaining('"password": "***"'), findsOneWidget);
  });

  testWidgets('records SSE events and WebSocket messages', (tester) async {
    await tester.pumpWidget(const NetoscopeExampleApp());

    Future<void> run(String label) async {
      await tester.scrollUntilVisible(find.text(label), 200);
      // Move the row clear of the floating inspector button.
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      // The demo streams mix fake and real asynchrony; advance both.
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(find.text('$label: done'), findsOneWidget);
    }

    await run('SSE stream (3 events)');
    // Connected + 3 events + closed.
    expect(find.text('5 requests recorded'), findsOneWidget);

    await run('WebSocket echo (simulated)');
    // Opened + 2 sent + 2 received + closed.
    expect(find.text('11 requests recorded'), findsOneWidget);
  });
}
