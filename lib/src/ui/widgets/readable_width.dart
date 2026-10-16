import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The widest a column of detail content grows on tablets and desktops.
/// Wider lines and stretched buttons are harder to scan.
const double readableContentWidth = 960;

/// Padding for a full-width scroll view that centers its content within
/// [readableContentWidth], keeping the scrollbar at the screen edge.
EdgeInsets readablePadding(
  BuildContext context, {
  double horizontal = 16,
  double top = 16,
  double bottom = 16,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = math.max(horizontal, (width - readableContentWidth) / 2);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}
