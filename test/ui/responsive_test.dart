// Renders every inspector screen at phone, tablet and desktop sizes, with
// large accessibility text, and fails on any overflow or layout error.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

const _sizes = <String, Size>{
  'iPhone SE (320)': Size(320, 568),
  'small Android (360)': Size(360, 640),
  'iPhone 16 (393)': Size(393, 852),
  'phone landscape': Size(852, 393),
  'iPad portrait': Size(768, 1024),
  'iPad landscape': Size(1180, 820),
  'desktop': Size(1440, 900),
};

const _textScales = [1.0, 1.3, 2.0];

final _t0 = DateTime.now().subtract(const Duration(minutes: 1));

List<NetworkLogEntry> _fixtures() => [
      NetworkLogEntry(
        id: 'login',
        method: 'POST',
        url: Uri.parse(
          'https://authentication.service.internal.example-company.com/'
          'api/v2/authentication/oauth2/token/exchange?client_id=mobile-app'
          '&redirect_uri=https%3A%2F%2Fexample.com%2Fcallback&state=xyz',
        ),
        timestamp: _t0,
        statusCode: 200,
        duration: const Duration(milliseconds: 1243),
        requestSize: 532,
        responseSize: 18234,
        tags: const [
          'login-flow',
          'onboarding-experiment-b',
          'very-long-tag-name'
        ],
        requestHeaders: const {
          'Authorization': '***',
          'X-Request-Correlation-Identifier':
              '6f1c2a90-77b4-4e1e-9d8a-3c5b1f0e2d4c',
        },
        requestBody: const NetworkLogBody(
          kind: NetworkBodyKind.json,
          content: '{"username":"ada.lovelace@analytical-engine.example.com",'
              '"password":"***","device":{"model":"iPhone16,2","os":"iOS 18.5"}}',
        ),
        responseBody: const NetworkLogBody(
          kind: NetworkBodyKind.json,
          content:
              '{"access_token":"***","refresh_token":"***","expires_in":3600,'
              '"user":{"id":1,"display_name":"Ada Lovelace Countess of Lovelace",'
              '"roles":["admin","developer","reviewer"]}}',
          contentType: 'application/json; charset=utf-8',
        ),
        details: [
          GraphQLDetails(
            operations: const [
              GraphQLOperation(
                name: 'ExchangeAuthenticationTokenForUserSessionWithDevice',
                type: GraphQLOperationType.mutation,
                document:
                    'mutation ExchangeAuthenticationTokenForUserSessionWithDevice'
                    r'($deviceIdentifier: ID!) { exchange(device: $deviceIdentifier) { token } }',
                variables:
                    '{"deviceIdentifier":"6f1c2a90-77b4-4e1e-9d8a-3c5b1f0e2d4c"}',
              ),
            ],
            errors: [
              GraphQLError(
                message: 'Not authorized to access field user.email on type '
                    'AuthenticatedUserProfile',
                path: const ['exchange', 'user', 'email'],
                code: 'FORBIDDEN_FIELD_ACCESS',
              ),
            ],
            hasData: true,
          ),
          const WebhookDetails(
            outcome: WebhookOutcome.retryable,
            attempt: 2,
            maxAttempts: 5,
            eventType: 'customer.subscription.trial_will_end',
            signatureAlgorithm: 'sha256',
          ),
        ],
      ),
      for (var i = 1; i <= 6; i++)
        NetworkLogEntry(
          id: 'u$i',
          method: 'GET',
          url:
              Uri.parse('https://api.example.com/users/$i/profile/preferences'),
          timestamp: _t0.add(Duration(milliseconds: 1300 + i * 30)),
          statusCode: 200,
          duration: Duration(milliseconds: 90 + i * 20),
          responseSize: 900,
        ),
      NetworkLogEntry(
        id: 'fail',
        method: 'DELETE',
        url: Uri.parse(
            'https://api.example.com/orders/123456789/items/987654321'),
        timestamp: _t0.add(const Duration(seconds: 2)),
        duration: const Duration(seconds: 30),
        error: const NetworkLogError(
          type: NetworkErrorType.timeout,
          message: 'The request timed out after 30 seconds while waiting for '
              'the server to respond to the deletion request',
        ),
      ),
      NetworkLogEntry(
        id: 'ws',
        method: 'WS',
        url: Uri.parse('wss://realtime.example.com/socket/v1/channels/prices'),
        timestamp: _t0.add(const Duration(seconds: 3)),
        protocol: NetworkProtocol.webSocket,
        kind: NetworkEventKind.message,
        direction: MessageDirection.incoming,
        connectionId: 'c1',
        responseSize: 48,
        responseBody: const NetworkLogBody(
          kind: NetworkBodyKind.json,
          content: '{"symbol":"NETO","price":101.25}',
        ),
        details: const [WebSocketDetails(frameType: WebSocketFrameType.text)],
      ),
      NetworkLogEntry(
        id: 'mqtt',
        method: 'MQTT',
        url: Uri.parse('mqtts://broker.example.com'),
        timestamp: _t0.add(const Duration(seconds: 4)),
        protocol: NetworkProtocol.mqtt,
        kind: NetworkEventKind.message,
        direction: MessageDirection.incoming,
        details: const [
          MqttDetails(
              topic: 'devices/warehouse-north-17/sensors/temperature/celsius',
              qos: 1),
        ],
      ),
    ];

/// One way into a screen of the inspector.
typedef _Navigate = Future<void> Function(WidgetTester tester);

/// Opens the row for [id], scrolling the lazily built list until it exists.
///
/// The row's callback is invoked directly: these tests check layout, and a
/// row scrolled to the edge can sit under the filter bar.
Future<void> _open(WidgetTester tester, String id) async {
  final row = find.byKey(ValueKey(id));
  await _scrollTo(tester, row);
  tester.widget<InkWell>(row).onTap!();
}

/// Taps [finder] after scrolling the visible page until it is built.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _scrollTo(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
}

/// Opens a toolbar destination, which moves into the More menu when the
/// toolbar is compact.
Future<void> _toolbar(WidgetTester tester, String label) async {
  final button = find.byTooltip(label);
  if (button.evaluate().isNotEmpty) return tester.tap(button);
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: vertical.hitTestable().last,
  );
}

final Map<String, _Navigate> _screens = {
  'list': (t) async {},
  'list search help': (t) async {
    await t.tap(find.byTooltip('Search syntax'));
  },
  'filter sheet': (t) async {
    await t.tap(find.byType(ActionChip).first);
  },
  'settings sheet': (t) async {
    await t.tap(find.byTooltip('Inspector settings'));
  },
  'more menu': (t) async {
    await t.tap(find.byTooltip('More'));
  },
  'detail overview': (t) async {
    await _open(t, 'login');
  },
  'detail request': (t) async {
    await _open(t, 'login');
    await t.pumpAndSettle();
    await _tapVisible(t, find.text('Request'));
  },
  'detail response tree': (t) async {
    await _open(t, 'login');
    await t.pumpAndSettle();
    await _tapVisible(t, find.text('Response'));
    await t.pumpAndSettle();
    await _tapVisible(t, find.text('Tree'));
  },
  'detail graphql': (t) async {
    await _open(t, 'login');
    await t.pumpAndSettle();
    await _tapVisible(t, find.text('GraphQL'));
  },
  'failed call': (t) async {
    await _open(t, 'fail');
  },
  'message payload': (t) async {
    await _open(t, 'ws');
    await t.pumpAndSettle();
    await _tapVisible(t, find.text('Payload'));
  },
  'statistics': (t) async {
    await _toolbar(t, 'Statistics');
  },
  'timeline': (t) async {
    await _toolbar(t, 'Timeline');
  },
};

void main() {
  for (final MapEntry(key: screen, value: navigate) in _screens.entries) {
    group(screen, () {
      for (final MapEntry(key: device, value: size) in _sizes.entries) {
        for (final scale in _textScales) {
          testWidgets('$device, text ×$scale', (tester) async {
            tester.view
              ..physicalSize = size * 2
              ..devicePixelRatio = 2;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue);

            final store = InMemoryNetworkLogStore();
            for (final entry in _fixtures()) {
              store.add(entry);
            }
            final netoscope = Netoscope(
              store: store,
              config: const NetworkLoggerConfig(
                consoleLogLevel: ConsoleLogLevel.none,
              ),
            );
            await tester.pumpWidget(
              MaterialApp(home: NetworkInspector(netoscope: netoscope)),
            );
            await tester.pumpAndSettle();
            await navigate(tester);
            await tester.pumpAndSettle();

            // Scroll through scrollable content so lazily built parts lay out.
            final scrollables = find.byType(Scrollable);
            for (var i = 0; i < 4; i++) {
              final vertical = scrollables.evaluate().where(
                    (e) =>
                        (e.widget as Scrollable).axisDirection ==
                        AxisDirection.down,
                  );
              if (vertical.isEmpty) break;
              await tester.drag(
                find.byWidget(vertical.last.widget),
                const Offset(0, -600),
                warnIfMissed: false,
              );
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
          });
        }
      }
    });
  }

  testWidgets('narrow toolbars move Timeline and Statistics into More',
      (tester) async {
    tester.view
      ..physicalSize = const Size(320, 568) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = InMemoryNetworkLogStore();
    for (final entry in _fixtures()) {
      store.add(entry);
    }
    final netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    await tester.pumpWidget(
      MaterialApp(home: NetworkInspector(netoscope: netoscope)),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Statistics'), findsNothing);
    expect(find.text('Network inspector'), findsOneWidget);
    await _toolbar(tester, 'Statistics');
    await tester.pumpAndSettle();
    expect(find.text('Success rate'), findsOneWidget);
  });

  testWidgets('detail content keeps a readable width on desktop',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = InMemoryNetworkLogStore();
    for (final entry in _fixtures()) {
      store.add(entry);
    }
    final netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    await tester.pumpWidget(
      MaterialApp(home: NetworkInspector(netoscope: netoscope)),
    );
    await tester.pumpAndSettle();
    await _open(tester, 'login');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.text('Copy cURL')).width, lessThan(960));
    final general = tester.getTopLeft(find.text('GENERAL'));
    expect(general.dx, greaterThan((1440 - 960) / 2 - 1));
  });

  testWidgets('right-to-left layout', (tester) async {
    tester.view
      ..physicalSize = const Size(393, 852) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = InMemoryNetworkLogStore();
    for (final entry in _fixtures()) {
      store.add(entry);
    }
    final netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: NetworkInspector(netoscope: netoscope),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _open(tester, 'login');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
