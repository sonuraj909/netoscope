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
}
