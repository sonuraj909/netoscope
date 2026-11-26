// material.dart is deprecated from Flutter 3.47 (use package:material_ui);
// kept until the minimum supported Flutter version reaches 3.47.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import '../../core/entities/network_log_entry.dart';
import '../../core/usecases/compare_network_logs.dart';
import '../theme/inspector_theme.dart';
import '../widgets/log_formatting.dart';
import '../widgets/readable_width.dart';
import '../widgets/section_card.dart';

/// Shows the differences between two recorded calls side by side.
class CompareScreen extends StatefulWidget {
  /// Compares [first] with [second]. The older call is shown as "A".
  const CompareScreen({super.key, required this.first, required this.second});

  /// One of the calls.
  final NetworkLogEntry first;

  /// The other call.
  final NetworkLogEntry second;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  late NetworkLogComparison _comparison = _compare(swapped: false);
  bool _swapped = false;
  bool _onlyDifferences = true;

  NetworkLogComparison _compare({required bool swapped}) {
    final olderFirst =
        !widget.second.timestamp.isBefore(widget.first.timestamp);
    final (a, b) = olderFirst
        ? (widget.first, widget.second)
        : (widget.second, widget.first);
    return swapped ? NetworkLogComparison(b, a) : NetworkLogComparison(a, b);
  }

  void _swap() => setState(() {
        _swapped = !_swapped;
        _comparison = _compare(swapped: _swapped);
      });

  int get _differenceCount => [
        ..._comparison.summary,
        ..._comparison.queryParameters,
        ..._comparison.requestHeaders,
        ..._comparison.responseHeaders,
      ].where((f) => f.change != NetworkLogDiffChange.unchanged).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = _comparison;
    final count = _differenceCount;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compare calls',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              c.hasDifferences
                  ? '$count field ${count == 1 ? 'difference' : 'differences'}'
                  : 'No differences apart from timing',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Swap A and B',
            icon: const Icon(Icons.swap_vert),
            onPressed: _swap,
          ),
          IconButton(
            tooltip: _onlyDifferences
                ? 'Show unchanged values'
                : 'Show only differences',
            isSelected: _onlyDifferences,
            icon: const Icon(Icons.filter_list),
            selectedIcon: const Icon(Icons.filter_list_alt),
            onPressed: () =>
                setState(() => _onlyDifferences = !_onlyDifferences),
          ),
        ],
      ),
      body: ListView(
        padding: readablePadding(context),
        children: [
          SectionCard(
            title: 'Calls',
            icon: Icons.compare_arrows,
            child: Column(
              children: [
                _CallRow(label: 'A', entry: c.before),
                const SizedBox(height: 6),
                _CallRow(label: 'B', entry: c.after),
              ],
            ),
          ),
          for (final (title, icon, fields) in [
            ('Summary', Icons.summarize_outlined, c.summary),
            ('Query parameters', Icons.tune, c.queryParameters),
            ('Request headers', Icons.north_east, c.requestHeaders),
            ('Response headers', Icons.south_west, c.responseHeaders),
          ])
            if (fields.isNotEmpty)
              SectionCard(
                title: title,
                icon: icon,
                child: _FieldTable(
                  fields: fields,
                  onlyDifferences: _onlyDifferences,
                ),
              ),
          for (final (title, lines) in [
            ('Request body', c.requestBody),
            ('Response body', c.responseBody),
          ])
            if (lines.isNotEmpty)
              SectionCard(
                title: title,
                icon: Icons.data_object,
                child: _LineDiffView(
                  lines: lines,
                  onlyDifferences: _onlyDifferences,
                ),
              ),
        ],
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.label, required this.entry});

  final String label;
  final NetworkLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: scheme.secondaryContainer,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${entry.method} ${entryTitle(entry)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: codeTextStyle.copyWith(fontSize: 12.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${formatTime(entry.timestamp)} · ${entryStatus(entry)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: outcomeColor(entry, scheme),
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _FieldTable extends StatelessWidget {
  const _FieldTable({required this.fields, required this.onlyDifferences});

  final List<NetworkLogFieldDiff> fields;
  final bool onlyDifferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = [
      for (final field in fields)
        if (!onlyDifferences || field.change != NetworkLogDiffChange.unchanged)
          field,
    ];
    if (shown.isEmpty) {
      return Text(
        'No differences.',
        style:
            theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    final removed = scheme.error;
    final added = successColor(scheme);
    final value = codeTextStyle.copyWith(fontSize: 12.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, field) in shown.indexed) ...[
          if (index > 0) const Divider(height: 14),
          Text(
            field.name,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: field.change == NetworkLogDiffChange.unchanged
                  ? scheme.onSurfaceVariant
                  : scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          if (field.change == NetworkLogDiffChange.unchanged)
            SelectableText(field.before ?? '–', style: value)
          else ...[
            _DiffValue(
              marker: '−',
              text: field.before ?? '(absent)',
              color: removed,
              absent: field.before == null,
              style: value,
            ),
            _DiffValue(
              marker: '+',
              text: field.after ?? '(absent)',
              color: added,
              absent: field.after == null,
              style: value,
            ),
          ],
        ],
      ],
    );
  }
}

class _DiffValue extends StatelessWidget {
  const _DiffValue({
    required this.marker,
    required this.text,
    required this.color,
    required this.absent,
    required this.style,
  });

  final String marker;
  final String text;
  final Color color;
  final bool absent;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(marker, style: style.copyWith(color: color)),
            const SizedBox(width: 6),
            Expanded(
              child: SelectableText(
                text,
                style: style.copyWith(
                  color: absent ? color.withAlpha(170) : null,
                  fontStyle: absent ? FontStyle.italic : null,
                ),
              ),
            ),
          ],
        ),
      );
}

/// A unified line diff. With [onlyDifferences], unchanged runs are folded
/// to a few lines of context.
class _LineDiffView extends StatelessWidget {
  const _LineDiffView({required this.lines, required this.onlyDifferences});

  final List<NetworkLogLineDiff> lines;
  final bool onlyDifferences;

  static const int _context = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final changed =
        lines.any((l) => l.change != NetworkLogDiffChange.unchanged);
    if (!changed && onlyDifferences) {
      return Text(
        'Identical (${lines.length} ${lines.length == 1 ? 'line' : 'lines'}).',
        style:
            theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    final style = codeTextStyle.copyWith(fontSize: 12, height: 1.45);
    final rows = <Widget>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (onlyDifferences && line.change == NetworkLogDiffChange.unchanged) {
        var end = i;
        while (end < lines.length &&
            lines[end].change == NetworkLogDiffChange.unchanged) {
          end++;
        }
        final keepBefore = i == 0 ? 0 : _context;
        final keepAfter = end == lines.length ? 0 : _context;
        if (end - i > keepBefore + keepAfter + 1) {
          for (var k = i; k < i + keepBefore; k++) {
            rows.add(_line(lines[k], style, scheme));
          }
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '⋯ ${end - i - keepBefore - keepAfter} unchanged lines',
                style: style.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          );
          for (var k = end - keepAfter; k < end; k++) {
            rows.add(_line(lines[k], style, scheme));
          }
          i = end;
          continue;
        }
      }
      rows.add(_line(line, style, scheme));
      i++;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _line(NetworkLogLineDiff line, TextStyle style, ColorScheme scheme) {
    final (marker, color) = switch (line.change) {
      NetworkLogDiffChange.added => ('+', successColor(scheme)),
      NetworkLogDiffChange.removed => ('−', scheme.error),
      _ => (' ', null),
    };
    return Container(
      color: color?.withAlpha(26),
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        '$marker ${line.text}',
        softWrap: false,
        style: style.copyWith(color: color),
      ),
    );
  }
}
