import 'dart:async';

// material.dart is deprecated from Flutter 3.47 (use package:material_ui);
// kept until the minimum supported Flutter version reaches 3.47.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/pending_network_call.dart';
import '../../core/entities/traffic_insights.dart';
import '../../network_inspector.dart';
import '../network_log_filter.dart';
import '../payload/payload_viewer.dart';
import '../theme/inspector_theme.dart';
import '../widgets/entry_actions.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/search_help_sheet.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/log_formatting.dart';
import 'compare_screen.dart';
import 'request_detail_screen.dart';
import 'statistics_screen.dart';
import 'timeline_screen.dart';

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
  StreamSubscription<List<PendingNetworkCall>>? _pendingSubscription;
  List<PendingNetworkCall> _pending = const [];
  // Refreshes the elapsed time of in-flight calls while there are any.
  Timer? _ticker;
  late NetworkLogFilter _filter = widget.initialFilter;
  TrafficInsights _insights = TrafficInsights.empty;

  void _setEntries(List<NetworkLogEntry> entries) {
    _entries = entries;
    _insights = widget.netoscope.config.trafficAnalyzer.analyze(entries);
  }

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
      unawaited(_pendingSubscription?.cancel());
      _listen();
    }
  }

  void _listen() {
    _setEntries(widget.netoscope.logs);
    unawaited(_settingsSubscription?.cancel());
    _settingsSubscription = widget.netoscope.settingsChanges.listen((_) {
      if (mounted) setState(() {});
    });
    _subscription = widget.netoscope.logChanges.listen((entries) {
      if (mounted) setState(() => _setEntries(entries));
    });
    _setPending(widget.netoscope.pendingCalls);
    _pendingSubscription = widget.netoscope.pendingChanges.listen((calls) {
      if (mounted) setState(() => _setPending(calls));
    });
  }

  void _setPending(List<PendingNetworkCall> calls) {
    _pending = calls;
    if (calls.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    } else {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_settingsSubscription?.cancel());
    unawaited(_pendingSubscription?.cancel());
    _ticker?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _updateFilter(NetworkLogFilter Function(NetworkLogFilter) update) =>
      setState(() => _filter = update(_filter));

  Future<void> _copy(String content, String message) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: content));
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share({required bool har}) async {
    final handler = widget.netoscope.exportHandler;
    if (handler == null) return;
    final stamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    try {
      await handler(
        NetoscopeExport(
          fileName: 'netoscope-$stamp.${har ? 'har' : 'json'}',
          mimeType: 'application/json',
          content: har
              ? widget.netoscope.exportHar()
              : widget.netoscope.exportJson(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not share: $error')),
      );
    }
  }

  Future<void> _onMenu(_MenuAction action) async {
    switch (action) {
      case _MenuAction.copyJson:
        await _copy(
          widget.netoscope.exportJson(),
          'Copied ${_entries.length} requests as JSON',
        );
      case _MenuAction.copyHar:
        await _copy(widget.netoscope.exportHar(), 'Copied as HAR');
      case _MenuAction.shareJson:
        await _share(har: false);
      case _MenuAction.shareHar:
        await _share(har: true);
      case _MenuAction.clear:
        await _confirmClear();
      case _MenuAction.timeline:
      case _MenuAction.statistics:
        break; // Handled where the visible entries are known.
    }
  }

  void _openEntry(NetworkLogEntry entry) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InspectorThemeScope(
            netoscope: widget.netoscope,
            child: RequestDetailScreen(
              entry: entry,
              slowThreshold: _slowThreshold,
              payloadViewers: widget.payloadViewers,
              onShowConnection:
                  _filter.connectionId == null ? _showConnection : null,
              redactionMask: widget.netoscope.config.redactionMask,
              insights: _insights,
              onShowCalls: _showCalls,
              onReplay: widget.netoscope.canReplay(entry)
                  ? () => widget.netoscope.replay(entry)
                  : null,
              onCompare: _comparable(entry).isEmpty
                  ? null
                  : () => _pickComparison(entry),
            ),
          ),
        ),
      );

  /// Other HTTP calls [entry] can be compared with: calls to the same
  /// endpoint first, newest first within each group.
  List<NetworkLogEntry> _comparable(NetworkLogEntry entry) {
    if (entry.kind != NetworkEventKind.exchange) return const [];
    bool sameEndpoint(NetworkLogEntry e) =>
        e.method == entry.method &&
        e.url.host == entry.url.host &&
        e.url.path == entry.url.path;
    final others = [
      for (final e in _entries)
        if (e.id != entry.id && e.kind == NetworkEventKind.exchange) e,
    ];
    return [
      ...others.where(sameEndpoint),
      ...others.where((e) => !sameEndpoint(e)),
    ];
  }

  Future<void> _pickComparison(NetworkLogEntry entry) async {
    final candidates = _comparable(entry);
    final navigator = Navigator.of(context);
    final picked = await showModalBottomSheet<NetworkLogEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _ComparePicker(
        entry: entry,
        candidates: candidates,
      ),
    );
    if (picked == null || !mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => InspectorThemeScope(
          netoscope: widget.netoscope,
          child: CompareScreen(first: entry, second: picked),
        ),
      ),
    );
  }

  void _showCalls(String title, NetworkLogFilter filter) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InspectorThemeScope(
            netoscope: widget.netoscope,
            child: RequestListScreen(
              netoscope: widget.netoscope,
              payloadViewers: widget.payloadViewers,
              title: title,
              initialFilter: filter,
            ),
          ),
        ),
      );

  void _openStatistics() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InspectorThemeScope(
            netoscope: widget.netoscope,
            child: StatisticsScreen(
              netoscope: widget.netoscope,
              onShowCalls: _showCalls,
            ),
          ),
        ),
      );

  void _openTimeline(List<NetworkLogEntry> visible) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InspectorThemeScope(
            netoscope: widget.netoscope,
            child: TimelineScreen(entries: visible, onOpenEntry: _openEntry),
          ),
        ),
      );

  Future<void> _openSearchHelp() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SearchHelpSheet(
          onExample: (example) {
            Navigator.of(sheetContext).pop();
            _search.text = example;
            _updateFilter((f) => f.copyWith(query: example));
          },
        ),
      );

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

  // The sheet paints its own surface and handle: the modal's are themed once,
  // when it opens, and would not follow a theme switch made from the sheet.
  Future<void> _openSettings() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (_) => InspectorSettingsSheet(netoscope: widget.netoscope),
      );

  Future<void> _openFilters() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FilterSheet(
          filter: _filter,
          entries: _entries,
          insights: _insights,
          onUpdate: _updateFilter,
        ),
      );

  void _showConnection(String connectionId) => _showCalls(
        'Connection events',
        NetworkLogFilter(connectionId: connectionId),
      );

  String _summary(List<NetworkLogEntry> visible, int inFlight) {
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
      if (inFlight > 0) '$inFlight in flight',
      if (failed > 0) '$failed with errors',
      if (slow > 0) '$slow slow',
    ].join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _filter.apply(
      _entries,
      slowThreshold: _slowThreshold,
      insights: _insights,
    );
    final pending = _filter.applyPending(_pending);
    final canShare = widget.netoscope.exportHandler != null;
    // On narrow phones, or with large text, Timeline and Statistics move into
    // the overflow menu so the title stays readable.
    final compact = MediaQuery.sizeOf(context).width /
            MediaQuery.textScalerOf(context).scale(1) <
        380;
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
              _summary(visible, pending.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
        actions: [
          if (!compact) ...[
            IconButton(
              tooltip: 'Timeline',
              icon: const Icon(Icons.view_timeline_outlined),
              onPressed: visible.isEmpty ? null : () => _openTimeline(visible),
            ),
            IconButton(
              tooltip: 'Statistics',
              icon: const Icon(Icons.insights_outlined),
              onPressed: _openStatistics,
            ),
          ],
          IconButton(
            tooltip: 'Inspector settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            enabled: compact || _entries.isNotEmpty,
            onSelected: (action) => switch (action) {
              _MenuAction.timeline => _openTimeline(visible),
              _MenuAction.statistics => _openStatistics(),
              _ => _onMenu(action),
            },
            itemBuilder: (context) => [
              if (compact) ...[
                PopupMenuItem(
                  value: _MenuAction.timeline,
                  enabled: visible.isNotEmpty,
                  child: const _MenuRow(
                    Icons.view_timeline_outlined,
                    'Timeline',
                  ),
                ),
                const PopupMenuItem(
                  value: _MenuAction.statistics,
                  child: _MenuRow(Icons.insights_outlined, 'Statistics'),
                ),
                const PopupMenuDivider(),
              ],
              PopupMenuItem(
                enabled: _entries.isNotEmpty,
                value: _MenuAction.copyJson,
                child: _MenuRow(Icons.data_object, 'Copy all as JSON'),
              ),
              PopupMenuItem(
                enabled: _entries.isNotEmpty,
                value: _MenuAction.copyHar,
                child: _MenuRow(Icons.description_outlined, 'Copy as HAR'),
              ),
              if (canShare) ...[
                PopupMenuItem(
                  enabled: _entries.isNotEmpty,
                  value: _MenuAction.shareJson,
                  child: _MenuRow(Icons.ios_share, 'Share JSON…'),
                ),
                PopupMenuItem(
                  enabled: _entries.isNotEmpty,
                  value: _MenuAction.shareHar,
                  child: _MenuRow(Icons.ios_share, 'Share HAR…'),
                ),
              ],
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: _entries.isNotEmpty,
                value: _MenuAction.clear,
                child: _MenuRow(Icons.delete_sweep_outlined, 'Clear history'),
              ),
            ],
          ),
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
                hintText: 'Search or filter, e.g. status:4xx method:POST',
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
                    ? IconButton(
                        tooltip: 'Search syntax',
                        icon: const Icon(Icons.help_outline, size: 18),
                        onPressed: _openSearchHelp,
                      )
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
            child: visible.isEmpty && pending.isEmpty
                ? _EmptyState(hasEntries: _entries.isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: pending.length + visible.length,
                    separatorBuilder: (_, __) => const Divider(indent: 36),
                    itemBuilder: (context, index) {
                      if (index < pending.length) {
                        return _PendingRow(call: pending[index]);
                      }
                      final entry = visible[index - pending.length];
                      return _RequestRow(
                        entry: entry,
                        slowThreshold: _slowThreshold,
                        redactionMask: widget.netoscope.config.redactionMask,
                        isDuplicate: _insights.duplicateIds.contains(entry.id),
                        isNPlusOne: _insights.nPlusOneIds.contains(entry.id),
                        onOpen: () => _openEntry(entry),
                      );
                    },
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
          if (filter.ids != null) ...[
            InputChip(
              label: Text('${filter.ids!.length} selected calls'),
              onDeleted: () => onUpdate((f) => f.copyWith(clearIds: true)),
            ),
            const _ChipGap(),
          ],
          if (filter.tag != null) ...[
            InputChip(
              label: Text('#${filter.tag}'),
              onDeleted: () => onUpdate((f) => f.copyWith(clearTag: true)),
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
    required this.redactionMask,
    required this.isDuplicate,
    required this.isNPlusOne,
    required this.onOpen,
  });

  final NetworkLogEntry entry;
  final Duration slowThreshold;
  final String redactionMask;
  final bool isDuplicate;
  final bool isNPlusOne;
  final VoidCallback onOpen;

  bool get _isMessage => entry.kind == NetworkEventKind.message;

  String get _measure {
    if (!_isMessage) return formatDuration(entry.duration);
    final size = entry.direction == MessageDirection.outgoing
        ? entry.requestSize
        : entry.responseSize;
    return formatBytes(size);
  }

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
      onTap: onOpen,
      onLongPress: () => showEntryActions(context, entry, mask: redactionMask),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
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
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.3,
                          ),
                          child: Text(
                            badge,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: codeTextStyle.copyWith(
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: methodColor(context, badge),
                            ),
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
                    Row(
                      children: [
                        // Findings sit on the second line so the trailing
                        // status column stays narrow on small screens.
                        if (isNPlusOne || isDuplicate || entry.hasGraphQLErrors)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.45,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isNPlusOne || isDuplicate) ...[
                                    LogBadge(
                                      label: isNPlusOne ? 'N+1' : 'DUP',
                                      color: warningColor(scheme),
                                      filled: true,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  if (entry.hasGraphQLErrors) ...[
                                    LogBadge(
                                      label: 'GQL ERR',
                                      color: scheme.error,
                                      filled: true,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            [
                              entry.url.host,
                              formatTime(entry.timestamp),
                              for (final tag in entry.tags) '#$tag',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // With large text on a narrow phone the status would push the
              // title out entirely, so it is capped and scaled down instead.
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.topEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        entryStatus(entry),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks the call to compare with.
class _ComparePicker extends StatelessWidget {
  const _ComparePicker({required this.entry, required this.candidates});

  final NetworkLogEntry entry;
  final List<NetworkLogEntry> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sameCount = candidates
        .takeWhile(
          (e) =>
              e.method == entry.method &&
              e.url.host == entry.url.host &&
              e.url.path == entry.url.path,
        )
        .length;
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        );
    Widget tile(NetworkLogEntry e) => ListTile(
          dense: true,
          title: Text(
            '${e.method} ${entryTitle(e)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: codeTextStyle.copyWith(fontSize: 12.5),
          ),
          subtitle: Text(
            [e.url.host, formatTime(e.timestamp)].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
          trailing: Text(
            entryStatus(e),
            style: theme.textTheme.labelLarge?.copyWith(
              color: outcomeColor(e, scheme),
              fontWeight: FontWeight.w700,
            ),
          ),
          onTap: () => Navigator.of(context).pop(e),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Compare with…',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (sameCount > 0) ...[
            header('Same endpoint'),
            for (final e in candidates.take(sameCount)) tile(e),
          ],
          if (candidates.length > sameCount) ...[
            header('Other calls'),
            for (final e in candidates.skip(sameCount)) tile(e),
          ],
        ],
      ),
    );
  }
}

/// A call that has been sent but has not finished yet.
class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.call});

  final PendingNetworkCall call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: muted,
      fontFeatures: tabularFigures,
    );
    final path = call.url.path.isEmpty ? '/' : call.url.path;
    return Semantics(
      label: '${call.method} $path, in flight',
      child: Padding(
        key: ValueKey('pending-${call.id}'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: SizedBox.square(
                  dimension: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.3,
                          ),
                          child: Text(
                            call.method,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: codeTextStyle.copyWith(
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: methodColor(context, call.method),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            path,
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
                      [
                        call.url.host,
                        formatTime(call.startedAt),
                        for (final tag in call.tags) '#$tag',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.topEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Pending',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(formatDuration(call.elapsed), style: small),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

enum _MenuAction {
  timeline,
  statistics,
  copyJson,
  copyHar,
  shareJson,
  shareHar,
  clear,
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      );
}
