import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/entities/graphql_details.dart';
import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/protocol_details.dart';
import '../../core/entities/webhook_details.dart';
import '../payload/built_in_viewers.dart';
import '../payload/code_block.dart';
import '../payload/payload_viewer.dart';
import '../payload/syntax_highlighter.dart';
import '../theme/inspector_theme.dart';
import '../widgets/entry_actions.dart';
import '../widgets/log_formatting.dart';
import '../widgets/section_card.dart';

/// Shows everything captured for a single event.
class RequestDetailScreen extends StatelessWidget {
  /// Creates the detail view for [entry].
  const RequestDetailScreen({
    super.key,
    required this.entry,
    this.slowThreshold = const Duration(seconds: 3),
    this.payloadViewers = const [],
    this.onShowConnection,
    this.redactionMask = '***',
  });

  /// The event shown.
  final NetworkLogEntry entry;

  /// Exchanges at least this slow are flagged.
  final Duration slowThreshold;

  /// Custom payload viewers, consulted before the built-in ones.
  final List<PayloadViewer> payloadViewers;

  /// Opens the list of events of a connection, when available.
  final void Function(String connectionId)? onShowConnection;

  /// The configured redaction mask, highlighted in payloads.
  final String redactionMask;

  List<(String, Widget)> _tabs() {
    final graphQL = entry.graphQL;
    return [
      (
        'Overview',
        _OverviewTab(
          entry: entry,
          slowThreshold: slowThreshold,
          mask: redactionMask,
        ),
      ),
      ...switch (entry.kind) {
        NetworkEventKind.message => [
            (
              'Payload',
              _PayloadTab(
                headers: const {},
                body: entry.messageBody,
                emptyBodyText: 'No payload captured.',
                viewers: payloadViewers,
                showHeaders: false,
              ),
            ),
          ],
        NetworkEventKind.connection => [
            ('Handshake', _HandshakeTab(entry: entry)),
          ],
        NetworkEventKind.exchange => [
            (
              'Request',
              _PayloadTab(
                headers: entry.requestHeaders,
                body: entry.requestBody,
                emptyBodyText: 'No request body captured.',
                viewers: payloadViewers,
              ),
            ),
            (
              'Response',
              entry.hasResponse || entry.responseBody != null
                  ? _PayloadTab(
                      headers: entry.responseHeaders,
                      body: entry.responseBody,
                      emptyBodyText: 'No response body captured.',
                      viewers: payloadViewers,
                    )
                  : const _EmptyTab(
                      icon: Icons.cloud_off_outlined,
                      text: 'No response was received.',
                    ),
            ),
          ],
      },
      if (graphQL != null) ('GraphQL', _GraphQLTab(details: graphQL)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final connectionId = entry.connectionId;
    final showConnection = onShowConnection;
    return RedactionMaskScope(
      mask: redactionMask,
      child: DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            title: _AppBarTitle(entry: entry),
            actions: [
              if (connectionId != null && showConnection != null)
                IconButton(
                  tooltip: 'View connection events',
                  icon: const Icon(Icons.timeline),
                  onPressed: () => showConnection(connectionId),
                ),
              if (canCopyAsCurl(entry))
                IconButton(
                  tooltip: 'Copy as cURL',
                  icon: const Icon(Icons.terminal),
                  onPressed: () =>
                      copyEntryAsCurl(context, entry, mask: redactionMask),
                ),
              IconButton(
                tooltip: 'Copy details as JSON',
                icon: const Icon(Icons.copy),
                onPressed: () => copyEntryAsJson(context, entry),
              ),
            ],
            bottom: TabBar(
              isScrollable: tabs.length > 3,
              tabAlignment: tabs.length > 3 ? TabAlignment.start : null,
              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
              unselectedLabelStyle:
                  Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Theme.of(context).colorScheme.outlineVariant,
              tabs: [for (final (label, _) in tabs) Tab(text: label)],
            ),
          ),
          body: TabBarView(children: [for (final (_, view) in tabs) view]),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.entry,
    required this.slowThreshold,
    required this.mask,
  });

  final NetworkLogEntry entry;
  final Duration slowThreshold;
  final String mask;

  @override
  Widget build(BuildContext context) {
    final error = entry.error;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Summary(entry: entry, slowThreshold: slowThreshold, mask: mask),
        if (error != null)
          SectionCard(
            title: 'Error',
            icon: Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            child: KeyValueTable(
              accent: Theme.of(context).colorScheme.error,
              rows: [
                MapEntry('Type', error.type.name),
                MapEntry('Message', error.message),
              ],
            ),
          ),
        SectionCard(
          title: 'General',
          icon: Icons.info_outline,
          child: KeyValueTable(
            rows: [
              if (entry.protocol != NetworkProtocol.http)
                MapEntry('Protocol', entry.protocol.label),
              if (entry.kind != NetworkEventKind.exchange)
                MapEntry('Event', entry.kind.name),
              if (entry.direction != null)
                MapEntry(
                  'Direction',
                  entry.direction == MessageDirection.outgoing
                      ? 'sent ↑'
                      : 'received ↓',
                ),
              if (entry.lifecycle != null)
                MapEntry('Lifecycle', entry.lifecycle!.name),
              MapEntry('Outcome', entry.outcome.name),
              MapEntry('Started', entry.timestamp.toLocal().toIso8601String()),
              if (entry.connectionId != null)
                MapEntry('Connection', entry.connectionId!),
            ],
          ),
        ),
        for (final details in entry.details)
          if (details is! GraphQLDetails)
            SectionCard(
              title: details.label,
              icon: _detailsIcon(details),
              child: KeyValueTable(rows: details.describe().entries.toList()),
            ),
        if (entry.metadata.isNotEmpty)
          SectionCard(
            title: 'Metadata',
            icon: Icons.label_outline,
            child: KeyValueTable(
              rows: entry.metadata.entries.toList(),
              monospaceValues: true,
            ),
          ),
        if (entry.kind == NetworkEventKind.exchange)
          SectionCard(
            title: 'Query parameters',
            icon: Icons.manage_search,
            child: KeyValueTable(
              rows: [
                for (final param in entry.queryParameters.entries)
                  MapEntry(param.key, param.value.join(', ')),
              ],
              emptyText: 'No query parameters.',
              monospaceValues: true,
            ),
          ),
      ],
    );
  }

  static IconData _detailsIcon(ProtocolDetails details) => switch (details) {
        WebhookDetails() => Icons.webhook,
        GrpcDetails() => Icons.hub_outlined,
        SseDetails() => Icons.podcasts,
        WebSocketDetails() => Icons.swap_vert,
        MqttDetails() => Icons.sensors,
        TransferDetails(:final direction) =>
          direction == TransferDirection.upload ? Icons.upload : Icons.download,
        _ => Icons.extension_outlined,
      };
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.entry});

  final NetworkLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = entryBadge(entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$badge ',
                style: codeTextStyle.copyWith(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: methodColor(context, badge),
                ),
              ),
              TextSpan(text: entryTitle(entry)),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          entry.url.host,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.entry,
    required this.slowThreshold,
    required this.mask,
  });

  final NetworkLogEntry entry;
  final Duration slowThreshold;
  final String mask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outcome = outcomeColor(entry, scheme);
    final slow = entry.isSlower(slowThreshold);
    final curl = canCopyAsCurl(entry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusPill(label: entryStatus(entry), color: outcome),
              if (entry.protocol != NetworkProtocol.http)
                LogBadge(
                  label: entry.protocol.label,
                  color: scheme.primary,
                  filled: true,
                ),
              if (entry.hasGraphQLErrors)
                LogBadge(label: 'GQL ERR', color: scheme.error, filled: true),
              if (slow)
                LogBadge(
                  label: 'SLOW',
                  color: warningColor(scheme),
                  filled: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              entry.url.toString(),
              style: codeTextStyle.copyWith(
                fontSize: 13,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _MetricsBar(
            metrics: [
              if (entry.kind != NetworkEventKind.message)
                (
                  'Duration',
                  formatDuration(entry.duration),
                  slow ? warningColor(scheme) : null,
                ),
              ('Sent', formatBytes(entry.requestSize), null),
              ('Received', formatBytes(entry.responseSize), null),
              ('Time', formatTime(entry.timestamp), null),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (curl) ...[
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        copyEntryAsCurl(context, entry, mask: mask),
                    icon: const Icon(Icons.terminal, size: 18),
                    label: const Text('Copy cURL'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => copyEntryAsJson(context, entry),
                  icon: const Icon(Icons.data_object, size: 18),
                  label: const Text('Copy JSON'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
          ),
        ],
      ),
    );
  }
}

/// Labelled values in one bordered bar; two rows on narrow screens.
class _MetricsBar extends StatelessWidget {
  const _MetricsBar({required this.metrics});

  final List<(String, String, Color?)> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget cell((String, String, Color?) metric) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.$1.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                metric.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: metric.$3 ?? scheme.onSurface,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        );

    Widget row(List<(String, String, Color?)> items) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, metric) in items.indexed) ...[
                if (index > 0) const VerticalDivider(width: 1),
                Expanded(child: cell(metric)),
              ],
            ],
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 120.0 * metrics.length) {
            return row(metrics);
          }
          final half = (metrics.length + 1) ~/ 2;
          return Column(
            children: [
              row(metrics.sublist(0, half)),
              const Divider(),
              row(metrics.sublist(half)),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class _HandshakeTab extends StatelessWidget {
  const _HandshakeTab({required this.entry});

  final NetworkLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Request headers',
          icon: Icons.north_east,
          child: KeyValueTable(
            rows: entry.requestHeaders.entries.toList(),
            emptyText: 'No headers captured.',
            monospaceValues: true,
          ),
        ),
        SectionCard(
          title: 'Response headers',
          icon: Icons.south_west,
          child: KeyValueTable(
            rows: entry.responseHeaders.entries.toList(),
            emptyText: 'No headers captured.',
            monospaceValues: true,
          ),
        ),
      ],
    );
  }
}

class _PayloadTab extends StatelessWidget {
  const _PayloadTab({
    required this.headers,
    required this.body,
    required this.emptyBodyText,
    required this.viewers,
    this.showHeaders = true,
  });

  final Map<String, String> headers;
  final NetworkLogBody? body;
  final String emptyBodyText;
  final List<PayloadViewer> viewers;
  final bool showHeaders;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showHeaders)
          SectionCard(
            title: 'Headers',
            icon: Icons.list_alt,
            trailing: headers.isEmpty
                ? null
                : Text(
                    '${headers.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
            child: KeyValueTable(
              rows: headers.entries.toList(),
              emptyText: 'No headers captured.',
              monospaceValues: true,
            ),
          ),
        _BodyCard(body: body, emptyText: emptyBodyText, viewers: viewers),
      ],
    );
  }
}

class _BodyCard extends StatelessWidget {
  const _BodyCard({
    required this.body,
    required this.emptyText,
    required this.viewers,
  });

  final NetworkLogBody? body;
  final String emptyText;
  final List<PayloadViewer> viewers;

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    final theme = Theme.of(context);
    if (body == null) {
      return SectionCard(
        title: 'Body',
        icon: Icons.description_outlined,
        child: Text(
          emptyText,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final type = body.contentType;
    return SectionCard(
      title: 'Body',
      icon: Icons.description_outlined,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LogBadge(
            label: body.format.label,
            color: theme.colorScheme.primary,
            filled: true,
          ),
          IconButton(
            tooltip: 'Copy body',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () =>
                copyWithConfirmation(context, body.content, 'Body copied'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (type != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                type,
                style: codeTextStyle.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          if (body.isTruncated)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: tint(warningColor(theme.colorScheme)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.content_cut,
                    size: 16,
                    color: warningColor(theme.colorScheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Truncated at the configured maximum body size.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: warningColor(theme.colorScheme),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          viewerFor(body, viewers).build(context, body),
        ],
      ),
    );
  }
}

class _GraphQLTab extends StatelessWidget {
  const _GraphQLTab({required this.details});

  final GraphQLDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = details.hasData;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Result',
          icon: Icons.fact_check_outlined,
          child: KeyValueTable(
            rows: [
              MapEntry(
                'Operations',
                '${details.operations.length}'
                    '${details.isBatch ? ' (batch)' : ''}',
              ),
              MapEntry('Errors', '${details.errors.length}'),
              MapEntry(
                'Data',
                hasData == null
                    ? 'response not captured'
                    : hasData
                        ? (details.isPartial
                            ? 'partial (with errors)'
                            : 'present')
                        : 'none',
              ),
            ],
          ),
        ),
        for (final (index, op) in details.operations.indexed)
          SectionCard(
            title: details.isBatch
                ? '#$index ${op.type.name} ${op.name ?? ''}'
                : '${op.type.name} ${op.name ?? '(anonymous)'}',
            icon: Icons.code,
            uppercaseTitle: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (op.persistedQueryHash != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SelectableText(
                      'Persisted query: ${op.persistedQueryHash}',
                    ),
                  ),
                if (op.document != null)
                  CodeBlock(
                    text: op.document!,
                    language: SyntaxLanguage.graphql,
                  ),
                if (op.variables != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'VARIABLES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  CodeBlock(
                    text: _prettyJson(op.variables!),
                    language: SyntaxLanguage.json,
                  ),
                ],
              ],
            ),
          ),
        if (details.errors.isNotEmpty)
          SectionCard(
            title: 'Errors',
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final error in details.errors)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.error.withAlpha(110),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.error_outline,
                                size: 16,
                                color: theme.colorScheme.error,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                error.message,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (error.path.isNotEmpty ||
                            error.code != null ||
                            error.operationIndex != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (error.path.isNotEmpty)
                                _Tag('Path: ${error.pathLabel}'),
                              if (error.code != null)
                                _Tag('Code: ${error.code}'),
                              if (error.operationIndex != null)
                                _Tag('Operation: #${error.operationIndex}'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String _prettyJson(String json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(json));
    } on FormatException {
      return json;
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        text,
        style: codeTextStyle.copyWith(
          fontSize: 11.5,
          height: 1.3,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
