// Renders the README / pub.dev screenshots of the new inspector features.
//
//   fvm flutter test tool/screenshots/screenshots_test.dart
//   ./tool/screenshots/encode.sh
//
// Real fonts are loaded so text renders as on a device. Output: PNGs in
// build/screenshots, encoded to screenshots/*.webp by encode.sh.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
// material.dart is deprecated from Flutter 3.47 (use package:material_ui);
// kept until the minimum supported Flutter version reaches 3.47.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

const _outDir = 'build/screenshots';
const _size = Size(393, 852);
const _pixelRatio = 2.0;

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable)
          .parent
          .parent
          .parent
          .parent
          .parent
          .parent
          .path;
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  await _loadFont('Roboto', [
    for (final weight in ['Regular', 'Medium', 'Bold', 'Light'])
      '$fonts/Roboto-$weight.ttf',
  ]);
  await _loadFont('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
  const mono = '/System/Library/Fonts/SFNSMono.ttf';
  if (File(mono).existsSync()) {
    for (final family in ['monospace', 'Menlo', 'Courier']) {
      await _loadFont(family, [mono]);
    }
  }
}

/// Responses are released by the test, so calls can be shown in flight.
class _DemoBackend implements HttpClientAdapter {
  final Map<String, Completer<void>> gates = {};

  /// Responses per path, served in order; the last one repeats.
  final Map<String, List<(int, Object)>> responses = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    final gate = gates[options.uri.path];
    if (gate != null) await gate.future;
    final queue = responses[options.uri.path];
    final (status, body) = queue == null || queue.isEmpty
        ? (200, {'ok': true})
        : (queue.length > 1 ? queue.removeAt(0) : queue.first);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    final text = jsonEncode(body);
    return ResponseBody.fromString(text, status, headers: {
      Headers.contentLengthHeader: ['${utf8.encode(text).length}'],
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

NetworkLogBody _json(Object value) => NetworkLogBody(
      kind: NetworkBodyKind.json,
      content: jsonEncode(value),
      contentType: 'application/json',
    );

int _seq = 0;

NetworkLogEntry _entry(
  DateTime base,
  int offsetMs,
  String method,
  String url, {
  int? status = 200,
  int durationMs = 140,
  Map<String, String> requestHeaders = const {
    'accept': 'application/json',
    'authorization': '***',
  },
  Map<String, String> responseHeaders = const {
    'content-type': 'application/json',
  },
  NetworkLogBody? requestBody,
  NetworkLogBody? responseBody,
  NetworkLogError? error,
  List<String> tags = const [],
}) =>
    NetworkLogEntry(
      id: 'demo-${_seq++}',
      method: method,
      url: Uri.parse(url),
      timestamp: base.add(Duration(milliseconds: offsetMs)),
      statusCode: status,
      duration: Duration(milliseconds: durationMs),
      requestHeaders: requestHeaders,
      responseHeaders: status == null ? const {} : responseHeaders,
      requestBody: requestBody,
      responseBody: responseBody,
      requestSize: requestBody?.content.length,
      responseSize: responseBody?.content.length,
      error: error,
      tags: tags,
    );

/// A shop app's traffic, oldest first.
List<NetworkLogEntry> _history(DateTime base) => [
      _entry(base, 0, 'GET', 'https://api.shopnest.dev/v1/products/42',
          durationMs: 184,
          responseBody: _json({
            'id': 42,
            'name': 'Trail Runner 2',
            'price': 129.0,
            'stock': 7,
          })),
      for (var i = 0; i < 3; i++)
        _entry(base, 220 + i * 24, 'GET',
            'https://api.shopnest.dev/v1/products/${42 + i}/reviews',
            durationMs: 120 + i * 14,
            responseBody: _json({'reviews': <Object>[], 'total': 0})),
      _entry(base, 490, 'POST', 'https://api.shopnest.dev/graphql',
          durationMs: 268,
          requestBody: _json({
            'operationName': 'RecentOrders',
            'query': 'query RecentOrders { orders(last: 3) { id total } }',
          }),
          responseBody: _json({
            'data': {
              'orders': [
                {'id': 'A-1031', 'total': 64.5},
              ],
            },
          })),
      _entry(base, 940, 'GET',
          'https://api.shopnest.dev/v1/recommendations?for=42',
          status: 503,
          durationMs: 2140,
          responseBody: _json({'error': 'upstream unavailable'})),
    ];

void main() {
  setUpAll(() async {
    await _loadFonts();
    // No keyboard focus rings in touch screenshots.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    Directory(_outDir).createSync(recursive: true);
  });

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    bool settle = true,
  }) async {
    // In-flight spinners never settle; a few frames are enough for them.
    settle
        ? await tester.pumpAndSettle()
        : await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final element = find.byType(MaterialApp).evaluate().first;
      final image = await captureImage(element);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<(Netoscope, _DemoBackend, Dio)> pumpInspector(
    WidgetTester tester,
  ) async {
    // flutter_test draws shadows as black outlines unless this is off. It is
    // restored at the end of each test.
    debugDisableShadows = false;
    tester.view
      ..physicalSize = _size * _pixelRatio
      ..devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    final base = DateTime.now().subtract(const Duration(seconds: 3));
    final store = InMemoryNetworkLogStore();
    for (final entry in _history(base)) {
      store.add(entry);
    }
    final netoscope = Netoscope(
      store: store,
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        enableReplay: true,
      ),
    );
    final backend = _DemoBackend();
    final dio = netoscope.attachDio(
      // Like many apps, HTTP errors are handled from the status code.
      Dio(
        BaseOptions(
          baseUrl: 'https://api.shopnest.dev',
          validateStatus: (_) => true,
        ),
      )..httpClientAdapter = backend,
    );
    // The cart updates are real calls, so they can be sent again and
    // compared: the first succeeds, the second runs out of stock.
    backend.responses['/v1/cart/items/TR2-BLU-42'] = [
      (
        200,
        {
          'sku': 'TR2-BLU-42',
          'quantity': 1,
          'available': 1,
          'reserved': true,
          'cartTotal': 129.0,
        },
      ),
      (
        409,
        {
          'sku': 'TR2-BLU-42',
          'quantity': 1,
          'available': 1,
          'reserved': false,
          'error': 'insufficient_stock',
        },
      ),
    ];
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.runAsync(() async {
      for (final quantity in [1, 2]) {
        await dio.put<Object?>(
          '/v1/cart/items/TR2-BLU-42',
          queryParameters: {'currency': 'EUR'},
          data: {'sku': 'TR2-BLU-42', 'quantity': quantity},
          options: Options(
            headers: {'Authorization': 'Bearer demo-token'},
            extra: {Netoscope.tagsKey: 'checkout'},
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: NetworkInspector(netoscope: netoscope),
      ),
    );
    return (netoscope, backend, dio);
  }

  testWidgets('request list with calls in flight', (tester) async {
    final (netoscope, backend, dio) = await pumpInspector(tester);
    final calls = <Future<Object?>>[];
    await tester.runAsync(() async {
      backend.gates['/v1/checkout'] = Completer();
      backend.gates['/v1/uploads/avatar'] = Completer();
      calls.add(
        dio.post<Object?>('/v1/checkout', data: {'cart': 'c-88'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1380));
      calls.add(
        dio.post<Object?>(
          'https://media.shopnest.dev/v1/uploads/avatar',
          data: 'x' * 2048,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 420));
    });
    // Pick up the in-flight rows and their elapsed times.
    await tester.pump(const Duration(seconds: 1));
    await shoot(tester, 'request_list', settle: false);

    await tester.runAsync(() async {
      for (final gate in backend.gates.values) {
        gate.complete();
      }
      await Future.wait(calls);
    });
    await tester.pump();
    await netoscope.dispose();
    debugDisableShadows = true;
  });

  testWidgets('detail actions: send again and compare', (tester) async {
    final (netoscope, _, _) = await pumpInspector(tester);
    // The 409 is the newest cart call.
    await tester.tap(find.text('/v1/cart/items/TR2-BLU-42').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await shoot(tester, 'request_actions');

    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.textContaining('PUT /v1/cart'),
      ),
    );
    await shoot(tester, 'compare');
    await netoscope.dispose();
    debugDisableShadows = true;
  });
}
