import 'package:flutter/material.dart';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/payload_format.dart';
import '../../core/entities/protocol_details.dart';
import '../network_log_filter.dart';

/// A bottom sheet with the less frequently used filters. Changes apply
/// immediately.
class FilterSheet extends StatefulWidget {
  /// Creates the sheet. [entries] provide the available choices.
  const FilterSheet({
    super.key,
    required this.filter,
    required this.entries,
    required this.onUpdate,
  });

  /// The filter when the sheet opened.
  final NetworkLogFilter filter;

  /// The recorded entries, used to offer only relevant choices.
  final List<NetworkLogEntry> entries;

  /// Applies a change to the screen's current filter.
  final void Function(NetworkLogFilter Function(NetworkLogFilter)) onUpdate;

  /// The number of active filters this sheet controls.
  static int activeCount(NetworkLogFilter f) => [
        f.protocols.isNotEmpty,
        f.direction != null,
        f.sseEventType != null,
        f.payloadFormat != null,
        f.timeRange != TimeRangeFilter.all,
        f.onlyGraphQL,
        f.onlyGraphQLErrors,
      ].where((active) => active).length;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late NetworkLogFilter _filter = widget.filter;

  void _update(NetworkLogFilter Function(NetworkLogFilter) change) {
    setState(() => _filter = change(_filter));
    widget.onUpdate(change);
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final protocols = {
      for (final e in entries) e.protocol,
      ..._filter.protocols,
    }.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final sseTypes = {
      for (final e in entries)
        if (e.detail<SseDetails>() case final SseDetails sse) sse.eventType,
    }.toList()
      ..sort();
    final formats = {
      for (final e in entries) ...[
        if (e.requestBody != null) e.requestBody!.format,
        if (e.responseBody != null) e.responseBody!.format,
      ],
    };
    final orderedFormats = [
      ...PayloadFormat.builtIn.where(formats.contains),
      ...formats.where((f) => !PayloadFormat.builtIn.contains(f)),
    ];
    final hasMessages = entries.any((e) => e.direction != null);
    final hasGraphQL = entries.any((e) => e.graphQL != null);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filters',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => _update(
                    (f) => NetworkLogFilter(
                      query: f.query,
                      connectionId: f.connectionId,
                    ),
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
            _Section(
              title: 'Protocol',
              children: [
                for (final protocol in protocols)
                  FilterChip(
                    label: Text(protocol.label),
                    selected: _filter.protocols.contains(protocol),
                    onSelected: (selected) => _update(
                      (f) => f.copyWith(
                        protocols: selected
                            ? {...f.protocols, protocol}
                            : ({...f.protocols}..remove(protocol)),
                      ),
                    ),
                  ),
              ],
            ),
            _Section(
              title: 'Time range',
              children: [
                for (final range in TimeRangeFilter.values)
                  ChoiceChip(
                    label: Text(range.label),
                    selected: _filter.timeRange == range,
                    onSelected: (_) =>
                        _update((f) => f.copyWith(timeRange: range)),
                  ),
              ],
            ),
            if (hasGraphQL)
              _Section(
                title: 'GraphQL',
                children: [
                  FilterChip(
                    label: const Text('GraphQL only'),
                    selected: _filter.onlyGraphQL,
                    onSelected: (v) =>
                        _update((f) => f.copyWith(onlyGraphQL: v)),
                  ),
                  FilterChip(
                    label: const Text('With GraphQL errors'),
                    selected: _filter.onlyGraphQLErrors,
                    onSelected: (v) =>
                        _update((f) => f.copyWith(onlyGraphQLErrors: v)),
                  ),
                ],
              ),
            if (hasMessages)
              _Section(
                title: 'Message direction',
                children: [
                  ChoiceChip(
                    label: const Text('Any'),
                    selected: _filter.direction == null,
                    onSelected: (_) =>
                        _update((f) => f.copyWith(clearDirection: true)),
                  ),
                  ChoiceChip(
                    label: const Text('Sent ↑'),
                    selected: _filter.direction == MessageDirection.outgoing,
                    onSelected: (_) => _update(
                      (f) => f.copyWith(direction: MessageDirection.outgoing),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Received ↓'),
                    selected: _filter.direction == MessageDirection.incoming,
                    onSelected: (_) => _update(
                      (f) => f.copyWith(direction: MessageDirection.incoming),
                    ),
                  ),
                ],
              ),
            if (sseTypes.isNotEmpty)
              _Section(
                title: 'SSE event type',
                children: [
                  for (final type in sseTypes)
                    FilterChip(
                      label: Text(type),
                      selected: _filter.sseEventType == type,
                      onSelected: (selected) => _update(
                        (f) => selected
                            ? f.copyWith(sseEventType: type)
                            : f.copyWith(clearSseEventType: true),
                      ),
                    ),
                ],
              ),
            if (orderedFormats.isNotEmpty)
              _Section(
                title: 'Payload format',
                children: [
                  for (final format in orderedFormats)
                    FilterChip(
                      label: Text(format.label),
                      selected: _filter.payloadFormat == format,
                      onSelected: (selected) => _update(
                        (f) => selected
                            ? f.copyWith(payloadFormat: format)
                            : f.copyWith(clearPayloadFormat: true),
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

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: children),
        ],
      ),
    );
  }
}
