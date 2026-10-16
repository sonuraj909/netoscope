import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../network_inspector.dart';
import 'payload/payload_viewer.dart';
import 'screens/request_list_screen.dart';
import 'theme/inspector_theme.dart';

final Expando<ValueNotifier<int>> _openInspectors =
    Expando('netoscope.openInspectors');

/// How many inspectors for [netoscope] are currently shown. The floating
/// button hides itself while this is above zero.
ValueListenable<int> openInspectorCount(Netoscope netoscope) =>
    _openInspectors[netoscope] ??= ValueNotifier(0);

void _adjustOpenCount(Netoscope netoscope, int delta) {
  final notifier = _openInspectors[netoscope] ??= ValueNotifier(0);
  // Deferred: this runs from initState/dispose, when listeners must not be
  // notified synchronously.
  scheduleMicrotask(() => notifier.value += delta);
}

/// The Netoscope inspector: a searchable list of recorded calls with
/// per-call details.
///
/// Usually opened with [NetoscopeInspector.openInspector] or a
/// `NetworkInspectorButton`, but it is a regular widget and can be embedded
/// anywhere. It uses its own neutral theme, following the host's brightness.
class NetworkInspector extends StatefulWidget {
  /// Creates an inspector showing the history of [netoscope].
  const NetworkInspector({
    super.key,
    required this.netoscope,
    this.payloadViewers = const [],
  });

  /// The logger whose history is shown.
  final Netoscope netoscope;

  /// Custom payload viewers, consulted before the built-in ones.
  final List<PayloadViewer> payloadViewers;

  /// A route that shows the inspector.
  static Route<void> route(
    Netoscope netoscope, {
    List<PayloadViewer> payloadViewers = const [],
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => NetworkInspector(
          netoscope: netoscope,
          payloadViewers: payloadViewers,
        ),
        settings: const RouteSettings(name: 'netoscope/inspector'),
      );

  @override
  State<NetworkInspector> createState() => _NetworkInspectorState();
}

class _NetworkInspectorState extends State<NetworkInspector> {
  @override
  void initState() {
    super.initState();
    _adjustOpenCount(widget.netoscope, 1);
  }

  @override
  void dispose() {
    _adjustOpenCount(widget.netoscope, -1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InspectorThemeScope(
        child: RequestListScreen(
          netoscope: widget.netoscope,
          payloadViewers: widget.payloadViewers,
        ),
      );
}

/// Opens the inspector from a [Netoscope] instance.
extension NetoscopeInspector on Netoscope {
  /// Pushes the [NetworkInspector] onto the nearest navigator.
  ///
  /// Does nothing when logging is disabled or
  /// [NetworkLoggerConfig.showInspector] is `false`.
  Future<void> openInspector(
    BuildContext context, {
    List<PayloadViewer> payloadViewers = const [],
  }) async {
    if (!isInspectorAvailable) return;
    await Navigator.of(context).push(
      NetworkInspector.route(this, payloadViewers: payloadViewers),
    );
  }

  /// Whether an inspector for this logger is currently shown.
  bool get isInspectorOpen => openInspectorCount(this).value > 0;

  /// Pushes the [NetworkInspector] onto [navigator], unless one is already
  /// open. Useful where no `BuildContext` is available, such as a
  /// notification tap handler with a navigator key.
  Future<void> openInspectorOn(
    NavigatorState navigator, {
    List<PayloadViewer> payloadViewers = const [],
  }) async {
    if (!isInspectorAvailable || isInspectorOpen) return;
    await navigator.push(
      NetworkInspector.route(this, payloadViewers: payloadViewers),
    );
  }
}
