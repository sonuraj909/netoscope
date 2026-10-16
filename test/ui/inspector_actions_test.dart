import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import '../support/fixtures.dart';

void main() {
  late Netoscope netoscope;
  String? clipboard;

  setUp(() {
    clipboard = null;
    final store = InMemoryNetworkLogStore()
      ..add(
        makeEntry(
          id: 'login',
          method: 'POST',
          url: 'https://api.dev/login',
          requestHeaders: {'Authorization': '***'},
          requestBody: const NetworkLogBody(
            kind: NetworkBodyKind.json,
            content: '{"user":"ada","password":"***"}',
          ),
          responseBody: const NetworkLogBody(
            kind: NetworkBodyKind.json,
            content: '{"profile":{"name":"Ada","roles":["admin","dev"]}}',
          ),
        ),
      );
    netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
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

  testWidgets('copies a request as cURL from the overview', (tester) async {
    await pump(tester);
    await tester.tap(find.text('/login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy cURL'));
    await tester.pump();

    expect(clipboard, startsWith("curl \\\n  'https://api.dev/login'"));
    expect(clipboard, contains("-H 'Authorization: ***'"));
    expect(
      clipboard,
      contains("--data-raw '{\"user\":\"ada\",\"password\":\"***\"}'"),
    );
    expect(
      find.text('cURL command copied (redacted values appear as ***)'),
      findsOneWidget,
    );
  });

  testWidgets('long-press offers cURL and JSON copies', (tester) async {
    await pump(tester);

    await tester.longPress(find.text('/login'));
    await tester.pumpAndSettle();
    expect(find.text('Copy as cURL'), findsOneWidget);

    await tester.tap(find.text('Copy as JSON'));
    await tester.pumpAndSettle();
    expect(clipboard, contains('"url": "https://api.dev/login"'));
  });

  testWidgets('JSON bodies switch between pretty and tree views',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('/login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Response'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('"name": "Ada"', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Tree'));
    await tester.pumpAndSettle();
    final roles = find.textContaining('"roles": ', findRichText: true);
    expect(roles, findsOneWidget);
    // Two levels open by default; deeper nodes start collapsed.
    expect(find.textContaining('2 items', findRichText: true), findsOneWidget);
    expect(find.textContaining('"admin"', findRichText: true), findsNothing);

    await tester.tap(roles);
    await tester.pumpAndSettle();
    expect(find.textContaining('"admin"', findRichText: true), findsOneWidget);

    await tester.tap(roles);
    await tester.pumpAndSettle();
    expect(find.textContaining('"admin"', findRichText: true), findsNothing);
  });
}
