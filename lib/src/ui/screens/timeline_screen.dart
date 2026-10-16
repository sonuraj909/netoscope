import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_entry.dart';
import '../theme/inspector_theme.dart';
import '../widgets/log_formatting.dart';

/// One row of the timeline.
class TimelineSpan {
  /// Creates a span. A `null` [end] draws a point.
  const TimelineSpan(this.entry, this.start, this.end);

  /// The event.
  final NetworkLogEntry entry;

  /// When it started.
  final DateTime start;

  /// When it ended, or `null` for instantaneous events.
  final DateTime? end;

  /// Builds spans for [entries], oldest start first. Exchanges span their
  /// duration; closed or failed connections span their lifetime; other
  /// events are points.
  static List<TimelineSpan> from(Iterable<NetworkLogEntry> entries) {
    final spans = [
      for (final entry in entries)
        switch (entry) {
          NetworkLogEntry(kind: NetworkEventKind.exchange, :final duration?) =>
            TimelineSpan(entry, entry.timestamp, entry.timestamp.add(duration)),
          NetworkLogEntry(
            kind: NetworkEventKind.connection,
            lifecycle: ConnectionLifecycle.closed || ConnectionLifecycle.failed,
            :final duration?,
          ) =>
            TimelineSpan(
                entry, entry.timestamp.subtract(duration), entry.timestamp),
          _ => TimelineSpan(entry, entry.timestamp, null),
        },
    ]..sort((a, b) => a.start.compareTo(b.start));
    return spans;
  }

  /// The status color for this span.
  Color get color {
    final code = entry.statusCode ?? 0;
    return switch (entry.outcome) {
      NetworkLogOutcome.success =>
        entry.hasGraphQLErrors ? StatusColors.warning : StatusColors.good,
      NetworkLogOutcome.httpError =>
        code >= 500 ? StatusColors.serious : StatusColors.warning,
      NetworkLogOutcome.failure => StatusColors.critical,
      NetworkLogOutcome.cancelled => StatusColors.neutral,
    };
  }
}

/// A Gantt-style view of when calls ran and how they overlapped.
class TimelineScreen extends StatefulWidget {
  /// Creates the timeline for [entries]. Tapping a row calls [onOpenEntry].
  const TimelineScreen({
    super.key,
    required this.entries,
    required this.onOpenEntry,
  });

  /// The events to show (typically the list's filtered entries).
  final List<NetworkLogEntry> entries;

  /// Opens an event's details.
  final ValueChanged<NetworkLogEntry> onOpenEntry;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

const double _rowHeight = 34;
const double _axisHeight = 28;
const double _chartPadding = 16;

class _TimelineScreenState extends State<TimelineScreen> {
  late final List<TimelineSpan> _spans = TimelineSpan.from(widget.entries);
  final ScrollController _barsScroll = ScrollController();
  final ScrollController _axisScroll = ScrollController();
  double? _pxPerMs;
  double _scaleStart = 1;
  double _availableWidth = 300;

  DateTime get _origin => _spans.first.start;

  double get _totalMs {
    var end = _origin;
    for (final span in _spans) {
      final last = span.end ?? span.start;
      if (last.isAfter(end)) end = last;
    }
    return math.max(end.difference(_origin).inMicroseconds / 1000, 1);
  }

  double _fit() =>
      math.max((_availableWidth - 2 * _chartPadding) / _totalMs, 1e-4);

  @override
  void initState() {
    super.initState();
    _barsScroll.addListener(() {
      if (_axisScroll.hasClients) _axisScroll.jumpTo(_barsScroll.offset);
    });
  }

  @override
  void dispose() {
    _barsScroll.dispose();
    _axisScroll.dispose();
    super.dispose();
  }

  void _zoom(double factor) => setState(() {
        final fit = _fit();
        _pxPerMs = ((_pxPerMs ?? fit) * factor).clamp(fit, fit * 400);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timeline',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              _spans.isEmpty
                  ? 'No events'
                  : '${_spans.length} events · ${_formatMs(_totalMs)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.zoom_out),
            onPressed: _spans.isEmpty ? null : () => _zoom(1 / 1.6),
          ),
          IconButton(
            tooltip: 'Fit',
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed:
                _spans.isEmpty ? null : () => setState(() => _pxPerMs = null),
          ),
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.zoom_in),
            onPressed: _spans.isEmpty ? null : () => _zoom(1.6),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _spans.isEmpty
          ? Center(
              child: Text(
                'No events to show.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // Labels widen with the text size, but never take more than
                // 40% of the screen from the bars.
                final scale =
                    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
                final labelWidth =
                    ((constraints.maxWidth >= 600 ? 220.0 : 128.0) * scale)
                        .clamp(96.0, constraints.maxWidth * 0.4);
                _availableWidth = constraints.maxWidth - labelWidth;
                final pxPerMs = _pxPerMs ?? _fit();
                final chartWidth = math.max(
                    _totalMs * pxPerMs + 2 * _chartPadding, _availableWidth);
                return Column(
                  children: [
                    const Divider(),
                    SizedBox(
                      height: _axisHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: labelWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'CALL',
                                  textScaler: MediaQuery.textScalerOf(context)
                                      .clamp(maxScaleFactor: 1.3),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _axisScroll,
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: CustomPaint(
                                size: Size(chartWidth, _axisHeight),
                                painter: _AxisPainter(
                                  totalMs: _totalMs,
                                  pxPerMs: pxPerMs,
                                  textStyle: _labelStyle(context),
                                  lineColor: scheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: labelWidth,
                              child: Column(
                                children: [
                                  for (final (index, span) in _spans.indexed)
                                    _RowLabel(
                                      span: span,
                                      banded: index.isOdd,
                                      onTap: () =>
                                          widget.onOpenEntry(span.entry),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onScaleStart: (_) => _scaleStart = pxPerMs,
                                onScaleUpdate: (details) {
                                  if (details.pointerCount < 2) return;
                                  final fit = _fit();
                                  setState(() => _pxPerMs =
                                      (_scaleStart * details.horizontalScale)
                                          .clamp(fit, fit * 400));
                                },
                                child: SingleChildScrollView(
                                  key:
                                      const ValueKey('netoscope-timeline-bars'),
                                  controller: _barsScroll,
                                  scrollDirection: Axis.horizontal,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) {
                                      final index = (details.localPosition.dy /
                                              _rowHeight)
                                          .floor();
                                      if (index >= 0 && index < _spans.length) {
                                        widget.onOpenEntry(_spans[index].entry);
                                      }
                                    },
                                    child: CustomPaint(
                                      size: Size(
                                        chartWidth,
                                        _spans.length * _rowHeight,
                                      ),
                                      painter: _BarsPainter(
                                        spans: _spans,
                                        origin: _origin,
                                        totalMs: _totalMs,
                                        pxPerMs: pxPerMs,
                                        surface: scheme.surface,
                                        band: scheme.surfaceContainerLow,
                                        grid: scheme.outlineVariant,
                                        textStyle: _labelStyle(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    // The legend is reference text; capping its scale keeps it
                    // from crowding out the chart on small phones.
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: const _Legend(),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// The theme's small label style (keeps the app's font), muted.
TextStyle _labelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
    fontSize: 10.5,
    color: theme.colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.w500,
    fontFeatures: tabularFigures,
  );
}

String _formatMs(double ms) {
  if (ms < 1) return '${(ms * 1000).round()} µs';
  if (ms < 1000) return '${ms.round()} ms';
  if (ms < 60000) {
    final seconds = ms / 1000;
    return '${seconds.toStringAsFixed(seconds < 10 ? 2 : 1)} s';
  }
  return '${(ms / 60000).toStringAsFixed(1)} min';
}

/// A tick step (ms) giving at least [minPx] pixels between ticks.
double _tickStep(double pxPerMs, {double minPx = 84}) {
  const steps = [
    1, 2, 5, 10, 20, 50, 100, 200, 250, 500, 1000, 2000, 5000, 10000, //
    15000, 30000, 60000, 120000, 300000, 600000,
  ];
  for (final step in steps) {
    if (step * pxPerMs >= minPx) return step.toDouble();
  }
  return steps.last.toDouble();
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.totalMs,
    required this.pxPerMs,
    required this.textStyle,
    required this.lineColor,
  });

  final double totalMs;
  final double pxPerMs;
  final TextStyle textStyle;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final step = _tickStep(pxPerMs);
    final tick = Paint()..color = lineColor;
    for (var ms = 0.0; ms <= totalMs + step; ms += step) {
      final x = _chartPadding + ms * pxPerMs;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, size.height - 5), Offset(x, size.height), tick);
      final painter = TextPainter(
        text: TextSpan(
          text: ms == 0 ? '0' : '+${_formatMs(ms)}',
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
          canvas, Offset(x + 3, (size.height - painter.height) / 2 - 2));
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.pxPerMs != pxPerMs ||
      old.totalMs != totalMs ||
      old.textStyle != textStyle;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.spans,
    required this.origin,
    required this.totalMs,
    required this.pxPerMs,
    required this.surface,
    required this.band,
    required this.grid,
    required this.textStyle,
  });

  final List<TimelineSpan> spans;
  final DateTime origin;
  final double totalMs;
  final double pxPerMs;
  final Color surface;
  final Color band;
  final Color grid;
  final TextStyle textStyle;

  double _x(DateTime time) =>
      _chartPadding + time.difference(origin).inMicroseconds / 1000 * pxPerMs;

  @override
  void paint(Canvas canvas, Size size) {
    // Alternate row bands and recessive gridlines.
    final bandPaint = Paint()..color = band;
    for (var i = 1; i < spans.length; i += 2) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * _rowHeight, size.width, _rowHeight),
        bandPaint,
      );
    }
    final step = _tickStep(pxPerMs);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var ms = 0.0; ms <= totalMs + step; ms += step) {
      final x = _chartPadding + ms * pxPerMs;
      if (x > size.width) break;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (final (index, span) in spans.indexed) {
      final centerY = index * _rowHeight + _rowHeight / 2;
      final paint = Paint()..color = span.color;
      final start = _x(span.start);
      final end = span.end;
      if (end == null) {
        // Point events: an 8px dot with a 2px surface ring.
        canvas
          ..drawCircle(Offset(start, centerY), 6, Paint()..color = surface)
          ..drawCircle(Offset(start, centerY), 4, paint);
        continue;
      }
      final width = math.max(_x(end) - start, 3.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(start, centerY - 6, width, 12),
          Radius.circular(math.min(4, width / 2)),
        ),
        paint,
      );
      final label = TextPainter(
        text: TextSpan(
          text: formatDuration(end.difference(span.start)),
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = start + width + 6;
      if (labelX + label.width <= size.width) {
        label.paint(canvas, Offset(labelX, centerY - label.height / 2));
      } else if (width >= label.width + 12) {
        // No room after the bar: label inside, in ink that contrasts with
        // the fill.
        final inside = TextPainter(
          text: TextSpan(
            text: label.text!.toPlainText(),
            style: textStyle.copyWith(
              color: span.color.computeLuminance() > 0.45
                  ? const Color(0xFF15181E)
                  : const Color(0xFFFFFFFF),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        inside.paint(
          canvas,
          Offset(start + width - inside.width - 6, centerY - inside.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.pxPerMs != pxPerMs ||
      old.spans != spans ||
      old.surface != surface ||
      old.textStyle != textStyle;
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({
    required this.span,
    required this.onTap,
    this.banded = false,
  });

  final TimelineSpan span;
  final VoidCallback onTap;
  final bool banded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = entryBadge(span.entry);
    final row = InkWell(
      onTap: onTap,
      child: SizedBox(
        height: _rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                badge.split(' ').first,
                maxLines: 1,
                style: codeTextStyle.copyWith(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: methodColor(context, badge),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entryTitle(span.entry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Rows have a fixed height shared with the bar painter, so very large
    // text is capped here to keep labels from clipping.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.4,
      child: Material(
        color:
            banded ? theme.colorScheme.surfaceContainerLow : Colors.transparent,
        child: row,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  static const List<(Color, String, bool)> _items = [
    (StatusColors.good, 'Success', false),
    (StatusColors.warning, '4xx / GraphQL errors', false),
    (StatusColors.serious, '5xx', false),
    (StatusColors.critical, 'Failed', false),
    (StatusColors.neutral, 'Cancelled', false),
    (StatusColors.good, 'Message / event', true),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (color, label, dot) in _items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: dot ? 8 : 14,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label, style: theme.textTheme.labelSmall),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
