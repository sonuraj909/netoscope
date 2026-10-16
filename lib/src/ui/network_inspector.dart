import 'package:flutter/material.dart';

import '../network_inspector.dart';
import 'screens/request_list_screen.dart';

/// The Netoscope inspector: a searchable list of recorded calls with
/// per-call details.
///
/// Usually opened with [NetoscopeInspector.openInspector] or a
/// `NetworkInspectorButton`, but it is a regular widget and can be embedded
/// anywhere.
class NetworkInspector extends StatelessWidget {
  /// Creates an inspector showing the history of [netoscope].
  const NetworkInspector({super.key, required this.netoscope});

  /// The logger whose history is shown.
  final Netoscope netoscope;

  /// A route that shows the inspector.
  static Route<void> route(Netoscope netoscope) => MaterialPageRoute<void>(
        builder: (_) => NetworkInspector(netoscope: netoscope),
        settings: const RouteSettings(name: 'netoscope/inspector'),
      );

  @override
  Widget build(BuildContext context) => RequestListScreen(netoscope: netoscope);
}

/// Opens the inspector from a [Netoscope] instance.
extension NetoscopeInspector on Netoscope {
  /// Pushes the [NetworkInspector] onto the nearest navigator.
  ///
  /// Does nothing when logging is disabled or
  /// [NetworkLoggerConfig.showInspector] is `false`.
  Future<void> openInspector(BuildContext context) async {
    if (!isInspectorAvailable) return;
    await Navigator.of(context).push(NetworkInspector.route(this));
  }
}
