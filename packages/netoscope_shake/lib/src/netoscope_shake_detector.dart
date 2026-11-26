import 'dart:async';

import 'package:flutter/foundation.dart';
// material.dart is deprecated from Flutter 3.47 (use package:material_ui);
// kept until the minimum supported Flutter version reaches 3.47.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:netoscope/netoscope.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'shake_detector.dart';

/// Opens the Netoscope inspector when the device is shaken.
///
/// Wrap the app content, typically in `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(
///   navigatorKey: navigatorKey,
///   builder: (context, child) => NetoscopeShakeDetector(
///     netoscope: netoscope,
///     navigatorKey: navigatorKey,
///     child: child!,
///   ),
/// )
/// ```
///
/// Listens to the accelerometer only while mounted and only when the
/// inspector is available ([Netoscope.isInspectorAvailable]), so it can stay
/// in the tree in release builds. Shaking while an inspector is already open
/// does nothing. On platforms without an accelerometer it does nothing.
class NetoscopeShakeDetector extends StatefulWidget {
  /// Creates the detector.
  const NetoscopeShakeDetector({
    super.key,
    required this.netoscope,
    required this.child,
    this.navigatorKey,
    this.enabled = true,
    this.threshold = 2.7,
    this.minJolts = 2,
    this.window = const Duration(milliseconds: 600),
    this.cooldown = const Duration(milliseconds: 1500),
    this.samplingPeriod = SensorInterval.uiInterval,
    this.payloadViewers = const [],
    this.onShake,
    this.accelerometerEvents,
  });

  /// The logger whose inspector is opened.
  final Netoscope netoscope;

  /// The app content.
  final Widget child;

  /// The navigator used to open the inspector. Required when this widget is
  /// placed above the app's [Navigator], as in `MaterialApp.builder`.
  /// Defaults to the nearest [Navigator] ancestor.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Whether shakes are detected. Set to `false` to stop listening to the
  /// accelerometer without removing the widget.
  final bool enabled;

  /// The total acceleration, in g, a sample must exceed to count as a jolt.
  /// See [ShakeDetector.threshold].
  final double threshold;

  /// How many jolts within [window] make a shake.
  final int minJolts;

  /// The time span in which [minJolts] jolts must occur.
  final Duration window;

  /// How long after a shake further shakes are ignored.
  final Duration cooldown;

  /// How often the accelerometer is sampled.
  final Duration samplingPeriod;

  /// Custom payload viewers passed to the inspector.
  final List<PayloadViewer> payloadViewers;

  /// Called on every detected shake, before the inspector is opened.
  final VoidCallback? onShake;

  /// The accelerometer samples to listen to. Defaults to
  /// `accelerometerEventStream()` from `sensors_plus`; pass a stream to
  /// supply samples yourself, for example in tests.
  final Stream<AccelerometerEvent>? accelerometerEvents;

  @override
  State<NetoscopeShakeDetector> createState() => _NetoscopeShakeDetectorState();
}

class _NetoscopeShakeDetectorState extends State<NetoscopeShakeDetector> {
  StreamSubscription<AccelerometerEvent>? _subscription;
  late ShakeDetector _detector;

  @override
  void initState() {
    super.initState();
    _detector = _createDetector();
    _listen();
  }

  @override
  void didUpdateWidget(NetoscopeShakeDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threshold != widget.threshold ||
        oldWidget.minJolts != widget.minJolts ||
        oldWidget.window != widget.window ||
        oldWidget.cooldown != widget.cooldown) {
      _detector = _createDetector();
    }
    if (oldWidget.netoscope != widget.netoscope ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.samplingPeriod != widget.samplingPeriod ||
        oldWidget.accelerometerEvents != widget.accelerometerEvents) {
      _cancel();
      _listen();
    }
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  ShakeDetector _createDetector() => ShakeDetector(
        threshold: widget.threshold,
        minJolts: widget.minJolts,
        window: widget.window,
        cooldown: widget.cooldown,
      );

  /// Platforms `sensors_plus` implements. Elsewhere the default stream is
  /// not opened at all, so no plugin errors are reported.
  static bool get _hasSensorPlugin =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _listen() {
    if (!widget.enabled || !widget.netoscope.isInspectorAvailable) return;
    final injected = widget.accelerometerEvents;
    if (injected == null && !_hasSensorPlugin) return;
    // sensors_plus starts platform calls it does not await; keep their
    // failures (for example a missing plugin) out of the app's error zone.
    runZonedGuarded(() {
      final events = injected ??
          accelerometerEventStream(samplingPeriod: widget.samplingPeriod);
      _subscription = events.listen(
        _onSample,
        // No accelerometer (simulators, unsupported devices): stay idle.
        onError: (Object _) => _cancel(),
        cancelOnError: true,
      );
    }, (_, __) {
      // Shake detection is best-effort and must never affect the app.
    });
  }

  void _cancel() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _onSample(AccelerometerEvent event) {
    if (!_detector.add(event.x, event.y, event.z, event.timestamp)) return;
    final netoscope = widget.netoscope;
    if (!netoscope.isInspectorAvailable || netoscope.isInspectorOpen) return;
    widget.onShake?.call();
    final navigator =
        widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (navigator == null) return;
    unawaited(
      netoscope.openInspectorOn(
        navigator,
        payloadViewers: widget.payloadViewers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
