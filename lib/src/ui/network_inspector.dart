import 'package:flutter/material.dart';

import '../network_inspector.dart';
import 'payload/payload_viewer.dart';
import 'screens/request_list_screen.dart';

/// The Netoscope inspector: a searchable list of recorded calls with
/// per-call details.
///
/// Usually opened with [NetoscopeInspector.openInspector] or a
/// `NetworkInspectorButton`, but it is a regular widget and can be embedded
/// anywhere.
class NetworkInspector extends StatelessWidget {
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
  Widget build(BuildContext context) => RequestListScreen(
        netoscope: netoscope,
        payloadViewers: payloadViewers,
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
}
