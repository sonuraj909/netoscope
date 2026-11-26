import 'dart:async';

import 'package:flutter/foundation.dart';

// material.dart is deprecated from Flutter 3.47 (use package:material_ui);
// kept until the minimum supported Flutter version reaches 3.47.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope_shake/netoscope_shake.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  late StreamController<AccelerometerEvent> samples;
  late DateTime clock;

  setUp(() {
    samples = StreamController<AccelerometerEvent>.broadcast();
    clock = DateTime(2026, 11, 26, 12);
  });

  tearDown(() => unawaited(samples.close()));

  Netoscope logger({bool enabled = true}) => Netoscope(
        config: NetworkLoggerConfig(
          enabled: enabled,
          consoleLogLevel: ConsoleLogLevel.none,
        ),
      );

  Future<void> shake(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      clock = clock.add(const Duration(milliseconds: 100));
      samples.add(AccelerometerEvent(35, 0, 0, clock));
    }
    await tester.pumpAndSettle();
  }

  Widget app(
    Netoscope netoscope, {
    bool enabled = true,
    VoidCallback? onShake,
    Stream<AccelerometerEvent>? events,
  }) {
    final navigatorKey = GlobalKey<NavigatorState>();
    return MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => NetoscopeShakeDetector(
        netoscope: netoscope,
        navigatorKey: navigatorKey,
        enabled: enabled,
        onShake: onShake,
        accelerometerEvents: events ?? samples.stream,
        child: child!,
      ),
      home: const Scaffold(body: Text('home')),
    );
  }

  testWidgets('opens the inspector on a shake', (tester) async {
    final netoscope = logger();
    await tester.pumpWidget(app(netoscope));
    expect(netoscope.isInspectorOpen, isFalse);

    await shake(tester);

    expect(netoscope.isInspectorOpen, isTrue);
    expect(find.byType(NetworkInspector), findsOneWidget);
  });

  testWidgets('works below the Navigator without a navigator key',
      (tester) async {
    final netoscope = logger();
    await tester.pumpWidget(
      MaterialApp(
        home: NetoscopeShakeDetector(
          netoscope: netoscope,
          accelerometerEvents: samples.stream,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );

    await shake(tester);

    expect(find.byType(NetworkInspector), findsOneWidget);
  });

  testWidgets('ignores gentle movement', (tester) async {
    final netoscope = logger();
    await tester.pumpWidget(app(netoscope));

    for (var i = 0; i < 10; i++) {
      clock = clock.add(const Duration(milliseconds: 100));
      samples.add(AccelerometerEvent(0, 0, 12, clock));
    }
    await tester.pumpAndSettle();

    expect(netoscope.isInspectorOpen, isFalse);
  });

  testWidgets('does not open a second inspector', (tester) async {
    final netoscope = logger();
    var shakes = 0;
    await tester.pumpWidget(app(netoscope, onShake: () => shakes++));

    await shake(tester);
    clock = clock.add(const Duration(seconds: 5));
    await shake(tester);

    expect(shakes, 1);
    expect(find.byType(NetworkInspector), findsOneWidget);
  });

  testWidgets('does nothing when the inspector is unavailable', (tester) async {
    final netoscope = logger(enabled: false);
    await tester.pumpWidget(app(netoscope));
    expect(samples.hasListener, isFalse);

    await shake(tester);

    expect(find.byType(NetworkInspector), findsNothing);
  });

  testWidgets('stops listening when disabled and when removed', (tester) async {
    final netoscope = logger();
    await tester.pumpWidget(app(netoscope));
    expect(samples.hasListener, isTrue);

    await tester.pumpWidget(app(netoscope, enabled: false));
    expect(samples.hasListener, isFalse);

    await tester.pumpWidget(app(netoscope));
    expect(samples.hasListener, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(samples.hasListener, isFalse);
  });

  testWidgets('stays idle when the sensor stream fails', (tester) async {
    final netoscope = logger();
    final failing = StreamController<AccelerometerEvent>();
    await tester.pumpWidget(app(netoscope, events: failing.stream));

    failing.addError(UnsupportedError('no accelerometer'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(failing.hasListener, isFalse);
    expect(find.text('home'), findsOneWidget);
    unawaited(failing.close());
  });

  testWidgets('default sensor stream without a plugin does not throw',
      (tester) async {
    final netoscope = logger();
    await tester.pumpWidget(
      MaterialApp(
        home: NetoscopeShakeDetector(
          netoscope: netoscope,
          child: const Text('home'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('does not open the sensor stream on desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final netoscope = logger();
    await tester.pumpWidget(
      MaterialApp(
        home: NetoscopeShakeDetector(
          netoscope: netoscope,
          child: const Text('home'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
