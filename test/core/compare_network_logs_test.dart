// material.dart is deprecated from Flutter 3.47 (use package:material_ui);
// kept until the minimum supported Flutter version reaches 3.47.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import '../support/fixtures.dart';

NetworkLogBody _json(String content) =>
    NetworkLogBody(kind: NetworkBodyKind.json, content: content);

List<String> _render(List<NetworkLogLineDiff> lines) =>
    [for (final line in lines) '$line'];

void main() {
  group('diffLines', () {
    test('marks inserted, removed and kept lines', () {
      final diff = NetworkLogComparison.diffLines('a\nb\nc\nd', 'a\nc\nx\nd');
      expect(_render(diff), ['  a', '- b', '  c', '+ x', '  d']);
    });

    test('handles absent and empty bodies', () {
      expect(NetworkLogComparison.diffLines(null, null), isEmpty);
      expect(_render(NetworkLogComparison.diffLines(null, 'x')), ['+ x']);
      expect(_render(NetworkLogComparison.diffLines('x', null)), ['- x']);
    });

    test('identical text has no changes', () {
      final diff = NetworkLogComparison.diffLines('a\nb', 'a\nb');
      expect(
        diff.every((l) => l.change == NetworkLogDiffChange.unchanged),
        isTrue,
      );
    });

    test('falls back for very long differing bodies', () {
      final a = List.generate(1500, (i) => 'a$i').join('\n');
      final b = List.generate(1500, (i) => 'b$i').join('\n');
      final diff = NetworkLogComparison.diffLines(a, b);
      expect(diff, hasLength(3000));
      expect(diff.first.change, NetworkLogDiffChange.removed);
      expect(diff.last.change, NetworkLogDiffChange.added);
    });
  });

  group('NetworkLogComparison', () {
    final before = makeEntry(
      id: 'a',
      url: 'https://api.dev/users?page=1&sort=name',
      requestHeaders: {'Accept': 'application/json', 'X-Trace': '1'},
      responseHeaders: {'content-type': 'application/json'},
      responseBody: _json('{"users":[{"id":1}],"total":1}'),
      duration: const Duration(milliseconds: 100),
    );
    final after = makeEntry(
      id: 'b',
      url: 'https://api.dev/users?page=2&sort=name',
      statusCode: 500,
      requestHeaders: {'accept': 'application/json', 'Authorization': '***'},
      responseHeaders: {'content-type': 'application/json'},
      responseBody: _json('{"users":[],"total":1}'),
      duration: const Duration(milliseconds: 900),
      timestamp: DateTime.utc(2026, 1, 1, 13),
    );

    test('compares the summary fields', () {
      final c = NetworkLogComparison(before, after);
      NetworkLogFieldDiff field(String name) =>
          c.summary.firstWhere((f) => f.name == name);
      expect(field('Method').change, NetworkLogDiffChange.unchanged);
      expect(field('Status').before, '200');
      expect(field('Status').after, '500');
      expect(field('Status').change, NetworkLogDiffChange.changed);
      expect(field('Duration').after, '900 ms');
      expect(c.hasDifferences, isTrue);
    });

    test('compares query parameters and headers by name', () {
      final c = NetworkLogComparison(before, after);
      expect(
        {for (final f in c.queryParameters) f.name: f.change},
        {
          'page': NetworkLogDiffChange.changed,
          'sort': NetworkLogDiffChange.unchanged,
        },
      );
      // Header names are case-insensitive.
      expect(
        {for (final f in c.requestHeaders) f.name: f.change},
        {
          'accept': NetworkLogDiffChange.unchanged,
          'authorization': NetworkLogDiffChange.added,
          'x-trace': NetworkLogDiffChange.removed,
        },
      );
    });

    test('compares JSON bodies pretty-printed', () {
      final c = NetworkLogComparison(before, after);
      final changed = [
        for (final line in c.responseBody)
          if (line.change != NetworkLogDiffChange.unchanged) '$line',
      ];
      expect(changed, contains('+   "users": [],'));
      expect(changed.where((l) => l.startsWith('-')), isNotEmpty);
      expect(
        c.responseBody.where((l) => l.text.contains('"total": 1')),
        hasLength(1),
        reason: 'unchanged lines appear once',
      );
    });

    test('identical calls differ only in timing', () {
      final twin = makeEntry(
        id: 'twin',
        url: 'https://api.dev/users?page=1&sort=name',
        requestHeaders: before.requestHeaders,
        responseHeaders: before.responseHeaders,
        responseBody: before.responseBody,
        duration: const Duration(milliseconds: 300),
      );
      expect(NetworkLogComparison(before, twin).hasDifferences, isFalse);
    });

    test('masked values compare equal', () {
      final a = makeEntry(id: 'a', requestHeaders: {'Authorization': '***'});
      final b = makeEntry(id: 'b', requestHeaders: {'Authorization': '***'});
      expect(
        NetworkLogComparison(a, b).requestHeaders.single.change,
        NetworkLogDiffChange.unchanged,
      );
    });
  });

  testWidgets('compares two calls from the detail screen', (tester) async {
    final store = InMemoryNetworkLogStore()
      ..add(
        makeEntry(
          id: 'old',
          url: 'https://api.dev/users?page=1',
          responseBody: _json('{"name":"Ada"}'),
        ),
      )
      ..add(
        makeEntry(
          id: 'new',
          url: 'https://api.dev/users?page=2',
          statusCode: 404,
          responseBody: _json('{"name":"Grace"}'),
          timestamp: DateTime.utc(2026, 1, 1, 13),
        ),
      )
      ..add(makeEntry(id: 'other', url: 'https://api.dev/orders'));
    final netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    addTearDown(netoscope.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NetworkInspector(netoscope: netoscope)),
    );
    await tester.tap(find.text('/users').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();

    // Calls to the same endpoint are offered first.
    expect(find.text('SAME ENDPOINT'), findsOneWidget);
    expect(find.text('OTHER CALLS'), findsOneWidget);
    await tester.tap(find.textContaining('GET /users').last);
    await tester.pumpAndSettle();

    expect(find.text('Compare calls'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('page'), findsOneWidget);
    expect(find.textContaining('"name": "Ada"'), findsOneWidget);
    expect(find.textContaining('"name": "Grace"'), findsOneWidget);

    // Showing unchanged values adds rows such as the method.
    expect(find.text('Method'), findsNothing);
    await tester.tap(find.byTooltip('Show unchanged values'));
    await tester.pumpAndSettle();
    expect(find.text('Method'), findsOneWidget);
  });
}
