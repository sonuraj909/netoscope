import 'package:flutter/material.dart';

import '../../core/entities/network_log_entry.dart';
import '../../core/entities/traffic_insights.dart';
import '../../core/entities/traffic_statistics.dart';
import '../../network_inspector.dart';
import '../network_log_filter.dart';
import '../theme/inspector_theme.dart';
import '../widgets/log_formatting.dart';
import '../widgets/readable_width.dart';
import '../widgets/section_card.dart';

/// Aggregate numbers, distributions and redundant-traffic findings for the
/// history, updated live.
class StatisticsScreen extends StatelessWidget {
  /// Creates the dashboard. [onShowCalls] opens a filtered call list.
  const StatisticsScreen({
    super.key,
    required this.netoscope,
    required this.onShowCalls,
  });

  /// The logger whose history is summarized.
  final Netoscope netoscope;

  /// Opens the calls matching a filter, titled [title].
  final void Function(String title, NetworkLogFilter filter) onShowCalls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<NetworkLogEntry>>(
      stream: netoscope.logChanges,
      initialData: netoscope.logs,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <NetworkLogEntry>[];
        final stats = TrafficStatistics.from(
          entries,
          slowThreshold: netoscope.config.slowRequestThreshold,
        );
        final insights = netoscope.config.trafficAnalyzer.analyze(entries);
        return Scaffold(
          appBar: AppBar(
            backgroundColor: theme.colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Statistics',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  stats.first == null
                      ? 'No events yet'
                      : '${stats.totalEvents} events since '
                          '${formatTime(stats.first!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          body: entries.isEmpty
              ? Center(
                  child: Text(
                    'Statistics appear once calls are recorded.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView(
                  padding: readablePadding(context, top: 8, bottom: 32),
                  children: [
                    _Tiles(stats: stats),
                    const SizedBox(height: 20),
                    if (stats.exchanges > 0)
                      SectionCard(
                        title: 'Status codes',
                        icon: Icons.donut_large_outlined,
                        child: _StatusBreakdown(
                          counts: stats.byStatusClass,
                          total: stats.exchanges,
                        ),
                      ),
                    if (!insights.isEmpty)
                      SectionCard(
                        title: 'Redundant traffic',
                        icon: Icons.content_copy_outlined,
                        color: warningColor(theme.colorScheme),
                        child: _InsightList(
                          insights: insights,
                          onShowCalls: onShowCalls,
                        ),
                      ),
                    if (stats.byMethod.isNotEmpty)
                      SectionCard(
                        title: 'Methods',
                        icon: Icons.alt_route,
                        child: _BarList(counts: stats.byMethod),
                      ),
                    if (stats.byProtocol.length > 1)
                      SectionCard(
                        title: 'Protocols',
                        icon: Icons.hub_outlined,
                        child: _BarList(counts: stats.byProtocol),
                      ),
                    SectionCard(
                      title: 'Hosts',
                      icon: Icons.dns_outlined,
                      child: _BarList(
                        counts: Map.fromEntries(stats.byHost.entries.take(5)),
                      ),
                    ),
                    if (stats.slowestEndpoints.isNotEmpty)
                      SectionCard(
                        title: 'Slowest endpoints',
                        icon: Icons.hourglass_bottom,
                        child: _EndpointList(
                          endpoints: stats.slowestEndpoints,
                          value: (e) => formatDuration(e.averageDuration),
                          caption: (e) =>
                              '${e.calls} ${e.calls == 1 ? 'call' : 'calls'} · average',
                        ),
                      ),
                    if (stats.busiestEndpoints.isNotEmpty)
                      SectionCard(
                        title: 'Most called endpoints',
                        icon: Icons.trending_up,
                        child: _EndpointList(
                          endpoints: stats.busiestEndpoints,
                          value: (e) => '${e.calls}×',
                          caption: (e) => e.failures == 0
                              ? 'no failures'
                              : '${e.failures} failed',
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats});

  final TrafficStatistics stats;

  @override
  Widget build(BuildContext context) {
    final rate = stats.successRate;
    final tiles = <(String, String, String?)>[
      ('Requests', '${stats.exchanges}', null),
      (
        'Success rate',
        rate == null
            ? '–'
            : '${(rate * 100).toStringAsFixed(rate == 1 ? 0 : 1)}%',
        null,
      ),
      ('Average', formatDuration(stats.averageDuration), null),
      (
        'p95',
        formatDuration(stats.p95Duration),
        'max ${formatDuration(stats.maxDuration)}'
      ),
      ('Received', formatBytes(stats.bytesReceived), null),
      ('Sent', formatBytes(stats.bytesSent), null),
      ('Slow', '${stats.slow}', null),
      (
        'Failed',
        '${stats.httpErrors + stats.failures + stats.cancelled}',
        stats.cancelled > 0 ? '${stats.cancelled} cancelled' : null,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (label, value, caption) in tiles)
              SizedBox(
                width: width,
                child: _StatTile(label: label, value: value, caption: caption),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// A stacked ratio bar (2px surface gaps, rounded outer ends) with a
/// labelled legend: color never carries the meaning alone.
class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({required this.counts, required this.total});

  final Map<String, int> counts;
  final int total;

  static const List<String> _order = ['2xx', '3xx', '4xx', '5xx', 'Failed'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final segments = [
      for (final key in _order)
        if ((counts[key] ?? 0) > 0) (key, counts[key]!),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (index, (key, count)) in segments.indexed) ...[
                    if (index > 0)
                      ColoredBox(
                        color: scheme.surfaceContainerLow,
                        child: const SizedBox(width: 2),
                      ),
                    Expanded(
                      flex: count,
                      child: ColoredBox(
                        color: StatusColors.forStatusClass(key),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final (key, count) in segments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: StatusColors.forStatusClass(key),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      key == 'Failed' ? 'Failed (no response)' : key,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '$count',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '${(count * 100 / total).round()}%',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal bars in one hue, value at the tip, label above.
class _BarList extends StatelessWidget {
  const _BarList({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final max = counts.values.fold<int>(0, (m, v) => v > m ? v : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final MapEntry(key: label, value: count) in counts.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: max == 0
                                  ? 0
                                  : (constraints.maxWidth * count / max)
                                      .clamp(4, constraints.maxWidth),
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$count',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EndpointList extends StatelessWidget {
  const _EndpointList({
    required this.endpoints,
    required this.value,
    required this.caption,
  });

  final List<EndpointStatistics> endpoints;
  final String Function(EndpointStatistics) value;
  final String Function(EndpointStatistics) caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final (index, endpoint) in endpoints.indexed) ...[
            if (index > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          endpoint.pattern,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: codeTextStyle.copyWith(
                            fontSize: 12.5,
                            height: 1.35,
                            color: scheme.onSurface,
                          ),
                        ),
                        Text(
                          caption(endpoint),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    value(endpoint),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightList extends StatelessWidget {
  const _InsightList({required this.insights, required this.onShowCalls});

  final TrafficInsights insights;
  final void Function(String title, NetworkLogFilter filter) onShowCalls;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = [
      for (final group in insights.nPlusOne)
        ('Possible N+1', group, Icons.account_tree_outlined),
      for (final group in insights.duplicates)
        ('Duplicate requests', group, Icons.content_copy_outlined),
    ];
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final (index, (kind, group, icon)) in items.indexed) ...[
            if (index > 0) const Divider(),
            InkWell(
              onTap: () => onShowCalls(
                kind,
                NetworkLogFilter(ids: {for (final e in group.entries) e.id}),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: warningColor(scheme)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$kind · ${group.count} calls in '
                            '${formatDuration(group.span)}',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            group.pattern,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: codeTextStyle.copyWith(
                              fontSize: 12,
                              height: 1.35,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
