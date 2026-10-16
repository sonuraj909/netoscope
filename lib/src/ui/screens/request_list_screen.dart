import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/network_log_entry.dart';
import '../../network_inspector.dart';
import '../network_log_filter.dart';
import '../widgets/log_formatting.dart';
import 'request_detail_screen.dart';

/// Lists recorded calls with search, filters, export and clearing.
class RequestListScreen extends StatefulWidget {
  /// Creates the list for [netoscope]'s history.
  const RequestListScreen({super.key, required this.netoscope});

  /// The logger whose history is shown.
  final Netoscope netoscope;

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  final TextEditingController _search = TextEditingController();
  late List<NetworkLogEntry> _entries;
  StreamSubscription<List<NetworkLogEntry>>? _subscription;
  NetworkLogFilter _filter = const NetworkLogFilter();

  Duration get _slowThreshold => widget.netoscope.config.slowRequestThreshold;

  @override
  void initState() {
    super.initState();
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
    _subscription = widget.netoscope.logChanges.listen((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
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

  @override
  Widget build(BuildContext context) {
    final visible = _filter.apply(_entries, slowThreshold: _slowThreshold);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network inspector'),
        actions: [
          IconButton(
            tooltip: 'Copy all as JSON',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _entries.isEmpty ? null : _export,
          ),
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_outline),
            onPressed: _entries.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search URL or endpoint',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _filter.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
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
          ),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? _EmptyState(hasEntries: _entries.isNotEmpty)
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) => _RequestTile(
                      entry: visible[index],
                      slowThreshold: _slowThreshold,
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
  });

  final NetworkLogFilter filter;
  final List<String> methods;
  final void Function(NetworkLogFilter Function(NetworkLogFilter)) onUpdate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          FilterChip(
            label: const Text('Slow'),
            avatar: const Icon(Icons.speed, size: 16),
            selected: filter.onlySlow,
            onSelected: (v) => onUpdate((f) => f.copyWith(onlySlow: v)),
          ),
          const _ChipGap(),
          for (final status in StatusFilter.values) ...[
            ChoiceChip(
              label: Text(status.label),
              selected: filter.status == status,
              onSelected: (_) => onUpdate((f) => f.copyWith(status: status)),
            ),
            const _ChipGap(),
          ],
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

class _ChipGap extends StatelessWidget {
  const _ChipGap();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 6);
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.entry, required this.slowThreshold});

  final NetworkLogEntry entry;
  final Duration slowThreshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = outcomeColor(entry, scheme);
    final path = entry.url.path.isEmpty ? '/' : entry.url.path;
    final slow = entry.isSlower(slowThreshold);
    return ListTile(
      key: ValueKey(entry.id),
      leading: SizedBox(
        width: 64,
        child: Align(
          alignment: Alignment.centerLeft,
          child: LogBadge(label: entry.method, color: scheme.primary),
        ),
      ),
      title: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.url.host} · ${formatTime(entry.timestamp)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          LogBadge(label: statusLabel(entry), color: color),
          const SizedBox(height: 4),
          Text(
            formatDuration(entry.duration),
            style: TextStyle(
              fontSize: 12,
              color: slow ? warningColor(scheme) : null,
              fontWeight: slow ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RequestDetailScreen(
            entry: entry,
            slowThreshold: slowThreshold,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasEntries});

  final bool hasEntries;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          hasEntries
              ? 'No requests match the current filters.'
              : 'No requests recorded yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
