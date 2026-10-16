import 'package:flutter/material.dart';

import '../../network_inspector.dart';
import '../network_inspector.dart';
import '../payload/payload_viewer.dart';

/// A small floating button that opens the [NetworkInspector].
///
/// Renders nothing when the inspector is unavailable (logging disabled or
/// [NetworkLoggerConfig.showInspector] is `false`), so it can stay in the
/// widget tree in every build mode.
///
/// When placed above the app's [Navigator] (for example in
/// `MaterialApp.builder`), pass the app's [navigatorKey].
class NetworkInspectorButton extends StatelessWidget {
  /// Creates the button.
  const NetworkInspectorButton({
    super.key,
    required this.netoscope,
    this.navigatorKey,
    this.payloadViewers = const [],
  });

  /// The logger whose inspector is opened.
  final Netoscope netoscope;

  /// The navigator used to open the inspector. Defaults to the nearest
  /// [Navigator] ancestor.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Custom payload viewers passed to the inspector.
  final List<PayloadViewer> payloadViewers;

  void _open(BuildContext context) {
    final navigator = navigatorKey?.currentState;
    if (navigator != null) {
      navigator.push(
        NetworkInspector.route(netoscope, payloadViewers: payloadViewers),
      );
    } else {
      netoscope.openInspector(context, payloadViewers: payloadViewers);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!netoscope.isInspectorAvailable) return const SizedBox.shrink();
    // No tooltip: this button may sit outside the Navigator's Overlay.
    return Semantics(
      button: true,
      label: 'Open network inspector',
      child: FloatingActionButton.small(
        heroTag: null,
        onPressed: () => _open(context),
        child: const Icon(Icons.network_check),
      ),
    );
  }
}

/// Places a [NetworkInspectorButton] over [child].
///
/// Designed for `MaterialApp.builder`:
///
/// ```dart
/// MaterialApp(
///   navigatorKey: navigatorKey,
///   builder: (context, child) => NetworkInspectorOverlay(
///     netoscope: netoscope,
///     navigatorKey: navigatorKey,
///     child: child!,
///   ),
/// )
/// ```
class NetworkInspectorOverlay extends StatelessWidget {
  /// Creates the overlay.
  const NetworkInspectorOverlay({
    super.key,
    required this.netoscope,
    required this.navigatorKey,
    required this.child,
    this.alignment = AlignmentDirectional.bottomStart,
    this.payloadViewers = const [],
  });

  /// The logger whose inspector is opened.
  final Netoscope netoscope;

  /// The app's navigator key, used to push the inspector.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Where the button is placed.
  final AlignmentGeometry alignment;

  /// The app content.
  final Widget child;

  /// Custom payload viewers passed to the inspector.
  final List<PayloadViewer> payloadViewers;

  @override
  Widget build(BuildContext context) {
    if (!netoscope.isInspectorAvailable) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: alignment,
                child: NetworkInspectorButton(
                  netoscope: netoscope,
                  navigatorKey: navigatorKey,
                  payloadViewers: payloadViewers,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
