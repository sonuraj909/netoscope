import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_entry.dart';
import '../../network_inspector.dart';
import '../network_log_filter.dart';
import '../payload/payload_viewer.dart';
import '../theme/inspector_theme.dart';
import '../widgets/entry_actions.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/log_formatting.dart';
import 'request_detail_screen.dart';

/// Lists recorded events with search, filters, export and clearing.
class RequestListScreen extends StatefulWidget {
  /// Creates the list for [netoscope]'s history.
  const RequestListScreen({
    super.key,
    required this.netoscope,
    this.initialFilter = const NetworkLogFilter(),
    this.payloadViewers = const [],
    this.title = 'Network inspector',
  });

  /// The logger whose history is shown.
  final Netoscope netoscope;

  /// The filter applied when the screen opens.
  final NetworkLogFilter initialFilter;

  /// Custom payload viewers, consulted before the built-in ones.
  final List<PayloadViewer> payloadViewers;

  /// The app bar title.
  final String title;

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  final TextEditingController _search = TextEditingController();
  late List<NetworkLogEntry> _entries;
  StreamSubscription<List<NetworkLogEntry>>? _subscription;
  StreamSubscription<Object?>? _settingsSubscription;
  late NetworkLogFilter _filter = widget.initialFilter;

  Duration get _slowThreshold => widget.netoscope.config.slowRequestThreshold;

  @override
  void initState() {
    super.initState();
    _search.text = _filter.query;
    _listen();
  }

  @override
  void didUpdateWidget(RequestListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.netoscope != widget.netoscope) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  void _listen() {
    _entries = widget.netoscope.logs;
    unawaited(_settingsSubscription?.cancel());
    _settingsSubscription = widget.netoscope.settingsChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _subscription = widget.netoscope.logChanges.listen((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_settingsSubscription?.cancel());
    _search.dispose();
    super.dispose();
  }

  void _updateFilter(NetworkLogFilter Function(NetworkLogFilter) update) =>
      setState(() => _filter = update(_filter));

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: widget.netoscope.exportJson()));
    messenger?.showSnackBar(
      SnackBar(content: Text('Copied ${_entries.length} requests as JSON')),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('All recorded requests will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) widget.netoscope.clearLogs();
  }

  Future<void> _openSettings() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => InspectorSettingsSheet(netoscope: widget.netoscope),
      );

  Future<void> _openFilters() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FilterSheet(
          filter: _filter,
          entries: _entries,
          onUpdate: _updateFilter,
        ),
      );

  void _showConnection(String connectionId) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InspectorThemeScope(
            child: RequestListScreen(
              netoscope: widget.netoscope,
              payloadViewers: widget.payloadViewers,
              title: 'Connection events',
              initialFilter: NetworkLogFilter(connectionId: connectionId),
            ),
          ),
        ),
      );

  String _summary(List<NetworkLogEntry> visible) {
    final failed = visible
        .where(
          (e) => e.outcome != NetworkLogOutcome.success || e.hasGraphQLErrors,
        )
        .length;
    final slow = visible.where((e) => e.isSlower(_slowThreshold)).length;
    final count = visible.length == _entries.length
        ? '${_entries.length} events'
        : '${visible.length} of ${_entries.length} events';
    return [
      count,
      if (failed > 0) '$failed with errors',
      if (slow > 0) '$slow slow',
    ].join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _filter.apply(_entries, slowThreshold: _slowThreshold);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              _summary(visible),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Inspector settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          IconButton(
            tooltip: 'Copy all as JSON',
            icon: const Icon(Icons.ios_share),
            onPressed: _entries.isEmpty ? null : _export,
          ),
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _entries.isEmpty ? null : _confirmClear,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (widget.netoscope.isEnabled && !widget.netoscope.isRecording)
            _PausedBanner(
              onResume: () => widget.netoscope.setLoggingEnabled(true),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextField(
              controller: _search,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Search URL, operation, event or topic',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _filter.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _search.clear();
                          _updateFilter((f) => f.copyWith(query: ''));
                        },
                      ),
              ),
              onChanged: (value) =>
                  _updateFilter((f) => f.copyWith(query: value)),
            ),
          ),
          _FilterBar(
            filter: _filter,
            methods: {for (final e in _entries) e.method}.toList()..sort(),
            onUpdate: _updateFilter,
            onOpenFilters: _openFilters,
          ),
          const Divider(),
          Expanded(
            child: visible.isEmpty
                ? _EmptyState(hasEntries: _entries.isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(indent: 36),
                    itemBuilder: (context, index) => _RequestRow(
                      entry: visible[index],
                      slowThreshold: _slowThreshold,
                      payloadViewers: widget.payloadViewers,
                      onShowConnection:
                          _filter.connectionId == null ? _showConnection : null,
                      redactionMask: widget.netoscope.config.redactionMask,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.methods,
    required this.onUpdate,
    required this.onOpenFilters,
  });

  final NetworkLogFilter filter;
  final List<String> methods;
  final void Function(NetworkLogFilter Function(NetworkLogFilter)) onUpdate;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final sheetCount = FilterSheet.activeCount(filter);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          ActionChip(
            avatar: Icon(
              Icons.tune,
              size: 16,
              color: sheetCount > 0 ? scheme.primary : null,
            ),
            label: Text(sheetCount == 0 ? 'Filters' : 'Filters ($sheetCount)'),
            side: sheetCount > 0 ? BorderSide(color: scheme.primary) : null,
            onPressed: onOpenFilters,
          ),
          const _ChipGap(),
          if (filter.connectionId != null) ...[
            InputChip(
              label: const Text('This connection'),
              onDeleted: () =>
                  onUpdate((f) => f.copyWith(clearConnection: true)),
            ),
            const _ChipGap(),
          ],
          FilterChip(
            label: const Text('Slow'),
            avatar: const Icon(Icons.speed, size: 16),
            selected: filter.onlySlow,
            onSelected: (v) => onUpdate((f) => f.copyWith(onlySlow: v)),
          ),
          const _ChipDivider(),
          for (final status in StatusFilter.values) ...[
            ChoiceChip(
              label: Text(status.label),
              selected: filter.status == status,
              onSelected: (_) => onUpdate((f) => f.copyWith(status: status)),
            ),
            const _ChipGap(),
          ],
          if (methods.isNotEmpty) const _ChipDivider(),
          for (final method in methods) ...[
            FilterChip(
              label: Text(method),
              selected: filter.method == method,
              onSelected: (selected) => onUpdate(
                (f) => selected
                    ? f.copyWith(method: method)
                    : f.copyWith(clearMethod: true),
              ),
            ),
            const _ChipGap(),
          ],
        ],
      ),
    );
  }
}

class _PausedBanner extends StatelessWidget {
  const _PausedBanner({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warningColor(theme.colorScheme);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Recording paused',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onResume, child: const Text('Resume')),
        ],
      ),
    );
  }
}

class _ChipGap extends StatelessWidget {
  const _ChipGap();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 6);
}

class _ChipDivider extends StatelessWidget {
  const _ChipDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: VerticalDivider(width: 1),
      );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.entry,
    required this.slowThreshold,
    required this.payloadViewers,
    required this.onShowConnection,
    required this.redactionMask,
  });

  final NetworkLogEntry entry;
  final Duration slowThreshold;
  final List<PayloadViewer> payloadViewers;
  final void Function(String connectionId)? onShowConnection;
  final String redactionMask;

  bool get _isMessage => entry.kind == NetworkEventKind.message;

  String get _measure {
    if (!_isMessage) return formatDuration(entry.duration);
    final size = entry.direction == MessageDirection.outgoing
        ? entry.requestSize
        : entry.responseSize;
    return formatBytes(size);
  }

  void _open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InspectorThemeScope(
            child: RequestDetailScreen(
              entry: entry,
              slowThreshold: slowThreshold,
              payloadViewers: payloadViewers,
              onShowConnection: onShowConnection,
              redactionMask: redactionMask,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outcome = outcomeColor(entry, scheme);
    final slow = entry.isSlower(slowThreshold);
    final badge = entryBadge(entry);
    final muted = scheme.onSurfaceVariant;
    // Color carries meaning: status codes and failures. Message formats and
    // lifecycle labels stay neutral.
    final statusColor = entry.kind == NetworkEventKind.exchange ||
            entry.outcome != NetworkLogOutcome.success
        ? outcome
        : muted;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: tabularFigures,
    );
    return InkWell(
      key: ValueKey(entry.id),
      onTap: () => _open(context),
      onLongPress: () => showEntryActions(context, entry, mask: redactionMask),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _StatusDot(color: outcome),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        badge,
                        style: codeTextStyle.copyWith(
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: methodColor(context, badge),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entryTitle(entry),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${entry.url.host} · ${formatTime(entry.timestamp)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.hasGraphQLErrors) ...[
                      LogBadge(
                        label: 'GQL ERR',
                        color: scheme.error,
                        filled: true,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      entryStatus(entry),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _measure,
                  style: small?.copyWith(
                    color: slow ? warningColor(scheme) : muted,
                    fontWeight: slow ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withAlpha(90), blurRadius: 4)],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasEntries});

  final bool hasEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasEntries ? Icons.filter_alt_off_outlined : Icons.wifi_tethering,
              size: 44,
              color: muted.withAlpha(150),
            ),
            const SizedBox(height: 14),
            Text(
              hasEntries
                  ? 'No requests match the current filters.'
                  : 'No requests recorded yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              hasEntries
                  ? 'Try a different search or reset the filters.'
                  : 'Network calls made through Netoscope appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
