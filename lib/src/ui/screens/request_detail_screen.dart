import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/entities/graphql_details.dart';
import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../payload/built_in_viewers.dart';
import '../payload/payload_viewer.dart';
import '../widgets/log_formatting.dart';

/// Shows everything captured for a single event.
class RequestDetailScreen extends StatelessWidget {
  /// Creates the detail view for [entry].
  const RequestDetailScreen({
    super.key,
    required this.entry,
    this.slowThreshold = const Duration(seconds: 3),
    this.payloadViewers = const [],
    this.onShowConnection,
  });

  /// The event shown.
  final NetworkLogEntry entry;

  /// Exchanges at least this slow are flagged.
  final Duration slowThreshold;

  /// Custom payload viewers, consulted before the built-in ones.
  final List<PayloadViewer> payloadViewers;

  /// Opens the list of events of a connection, when available.
  final void Function(String connectionId)? onShowConnection;

  List<(String, Widget)> _tabs() {
    final graphQL = entry.graphQL;
    return [
      ('Overview', _OverviewTab(entry: entry, slowThreshold: slowThreshold)),
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
            (
              'Handshake',
              _HandshakeTab(entry: entry),
            ),
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
                  : const Center(child: Text('No response was received.')),
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
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${entryBadge(entry)} ${entryStatus(entry)}'),
          actions: [
            if (connectionId != null && showConnection != null)
              IconButton(
                tooltip: 'View connection events',
                icon: const Icon(Icons.timeline),
                onPressed: () => showConnection(connectionId),
              ),
            IconButton(
              tooltip: 'Copy details as JSON',
              icon: const Icon(Icons.copy),
              onPressed: () => copyWithConfirmation(
                context,
                const JsonEncoder.withIndent('  ').convert(entry.toJson()),
                'Request details copied',
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: tabs.length > 3,
            tabs: [for (final (label, _) in tabs) Tab(text: label)],
          ),
        ),
        body: TabBarView(children: [for (final (_, view) in tabs) view]),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.entry, required this.slowThreshold});

  final NetworkLogEntry entry;
  final Duration slowThreshold;

  @override
  Widget build(BuildContext context) {
    final error = entry.error;
    final slow = entry.isSlower(slowThreshold) ? ' (slow)' : '';
    final isMessage = entry.kind == NetworkEventKind.message;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        KeyValueSection(
          title: 'General',
          values: {
            'URL': entry.url.toString(),
            if (entry.protocol != NetworkProtocol.http)
              'Protocol': entry.protocol.label,
            'Method': entry.method,
            if (entry.kind != NetworkEventKind.exchange)
              'Event': entry.kind.name,
            if (entry.direction != null)
              'Direction': entry.direction == MessageDirection.outgoing
                  ? 'sent ↑'
                  : 'received ↓',
            if (entry.lifecycle != null) 'Lifecycle': entry.lifecycle!.name,
            'Status': entryStatus(entry),
            'Outcome': entry.outcome.name,
            if (!isMessage)
              'Duration': '${formatDuration(entry.duration)}$slow',
            'Time': entry.timestamp.toLocal().toIso8601String(),
            if (!isMessage || entry.requestSize != null)
              'Request size': formatBytes(entry.requestSize),
            if (!isMessage || entry.responseSize != null)
              'Response size': formatBytes(entry.responseSize),
            if (entry.connectionId != null) 'Connection': entry.connectionId!,
          },
        ),
        if (error != null)
          KeyValueSection(
            title: 'Error',
            values: {'Type': error.type.name, 'Message': error.message},
          ),
        for (final details in entry.details)
          if (details is! GraphQLDetails)
            KeyValueSection(title: details.label, values: details.describe()),
        if (entry.metadata.isNotEmpty)
          KeyValueSection(title: 'Metadata', values: entry.metadata),
        if (entry.kind == NetworkEventKind.exchange)
          KeyValueSection(
            title: 'Query parameters',
            values: {
              for (final param in entry.queryParameters.entries)
                param.key: param.value.join(', '),
            },
            emptyText: 'No query parameters.',
          ),
      ],
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
        KeyValueSection(
          title: 'Request headers',
          values: entry.requestHeaders,
          emptyText: 'No headers captured.',
        ),
        KeyValueSection(
          title: 'Response headers',
          values: entry.responseHeaders,
          emptyText: 'No headers captured.',
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
          KeyValueSection(
            title: 'Headers',
            values: headers,
            emptyText: 'No headers captured.',
          ),
        _BodyView(body: body, emptyText: emptyBodyText, viewers: viewers),
      ],
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
        KeyValueSection(
          title: 'Result',
          values: {
            'Operations': '${details.operations.length}'
                '${details.isBatch ? ' (batch)' : ''}',
            'Errors': '${details.errors.length}',
            'Data': hasData == null
                ? 'response not captured'
                : hasData
                    ? (details.isPartial ? 'partial (with errors)' : 'present')
                    : 'none',
          },
        ),
        for (final (index, op) in details.operations.indexed) ...[
          SectionTitle(
            details.isBatch
                ? '#$index ${op.type.name} ${op.name ?? ''}'
                : '${op.type.name} ${op.name ?? '(anonymous)'}',
          ),
          if (op.persistedQueryHash != null)
            Text('Persisted query: ${op.persistedQueryHash}'),
          if (op.document != null) _Code(op.document!),
          if (op.variables != null) ...[
            const SizedBox(height: 8),
            Text('Variables', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            _Code(_prettyJson(op.variables!)),
          ],
          const SizedBox(height: 8),
        ],
        if (details.errors.isNotEmpty) const SectionTitle('Errors'),
        for (final error in details.errors)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    error.message,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  if (error.path.isNotEmpty) Text('Path: ${error.pathLabel}'),
                  if (error.code != null) Text('Code: ${error.code}'),
                  if (error.operationIndex != null)
                    Text('Operation: #${error.operationIndex}'),
                ],
              ),
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

class _Code extends StatelessWidget {
  const _Code(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}

/// A section heading with an optional trailing action.
class SectionTitle extends StatelessWidget {
  /// Creates a heading.
  const SectionTitle(this.text, {super.key, this.trailing});

  /// The heading text.
  final String text;

  /// An optional trailing widget.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A titled list of selectable key/value pairs.
class KeyValueSection extends StatelessWidget {
  /// Creates a section.
  const KeyValueSection({
    super.key,
    required this.title,
    required this.values,
    this.emptyText = '–',
  });

  /// The section title.
  final String title;

  /// The pairs shown.
  final Map<String, String> values;

  /// Shown when [values] is empty.
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final keyStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        if (values.isEmpty) Text(emptyText),
        for (final entry in values.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: keyStyle),
                SelectableText(entry.value),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _BodyView extends StatelessWidget {
  const _BodyView({
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
    if (body == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const SectionTitle('Body'), Text(emptyText)],
      );
    }
    final theme = Theme.of(context);
    final type = body.contentType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Body (${body.format.label})',
          trailing: IconButton(
            tooltip: 'Copy body',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () =>
                copyWithConfirmation(context, body.content, 'Body copied'),
          ),
        ),
        if (type != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(type, style: theme.textTheme.bodySmall),
          ),
        if (body.isTruncated)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Truncated at the configured maximum body size.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: warningColor(theme.colorScheme)),
            ),
          ),
        viewerFor(body, viewers).build(context, body),
      ],
    );
  }
}
