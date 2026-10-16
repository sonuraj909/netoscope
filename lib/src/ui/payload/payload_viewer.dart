import 'package:flutter/widgets.dart';

import '../../core/entities/network_log_body.dart';

/// Renders a captured payload in the inspector.
///
/// Register custom viewers with `NetworkInspector(payloadViewers: …)` (or
/// the same parameter on `openInspector`, `NetworkInspectorButton` and
/// `NetworkInspectorOverlay`). They are consulted before the built-in
/// viewers; the first whose [canView] returns `true` is used.
///
/// The body is already redacted and bounded by
/// `NetworkLoggerConfig.maxBodySize`. Keep [build] cheap: avoid synchronous
/// work proportional to the body size.
abstract class PayloadViewer {
  /// Allows const subclasses.
  const PayloadViewer();

  /// Whether this viewer can render [body].
  bool canView(NetworkLogBody body);

  /// Builds the view for [body].
  Widget build(BuildContext context, NetworkLogBody body);
}
