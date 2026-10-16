import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../widgets/log_formatting.dart';

/// Shows everything captured for a single call.
class RequestDetailScreen extends StatelessWidget {
  /// Creates the detail view for [entry].
  const RequestDetailScreen({
    super.key,
    required this.entry,
    this.slowThreshold = const Duration(seconds: 3),
  });

  /// The call shown.
  final NetworkLogEntry entry;

  /// Calls at least this slow are flagged.
  final Duration slowThreshold;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final json = const JsonEncoder.withIndent('  ').convert(entry.toJson());
    await Clipboard.setData(ClipboardData(text: json));
    messenger?.showSnackBar(
      const SnackBar(content: Text('Request details copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${entry.method} ${statusLabel(entry)}'),
          actions: [
            IconButton(
              tooltip: 'Copy details as JSON',
              icon: const Icon(Icons.copy),
              onPressed: () => _copy(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Request'),
              Tab(text: 'Response'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(entry: entry, slowThreshold: slowThreshold),
            _PayloadTab(
              headers: entry.requestHeaders,
              body: entry.requestBody,
              emptyBodyText: 'No request body captured.',
            ),
            entry.hasResponse
                ? _PayloadTab(
                    headers: entry.responseHeaders,
                    body: entry.responseBody,
                    emptyBodyText: 'No response body captured.',
                  )
                : const Center(child: Text('No response was received.')),
          ],
        ),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _KeyValueSection(
          title: 'General',
          values: {
            'URL': entry.url.toString(),
            'Method': entry.method,
            'Status': statusLabel(entry),
            'Outcome': entry.outcome.name,
            'Duration': '${formatDuration(entry.duration)}$slow',
            'Started': entry.timestamp.toLocal().toIso8601String(),
            'Request size': formatBytes(entry.requestSize),
            'Response size': formatBytes(entry.responseSize),
          },
        ),
        if (error != null)
          _KeyValueSection(
            title: 'Error',
            values: {'Type': error.type.name, 'Message': error.message},
          ),
        _KeyValueSection(
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

class _PayloadTab extends StatelessWidget {
  const _PayloadTab({
    required this.headers,
    required this.body,
    required this.emptyBodyText,
  });

  final Map<String, String> headers;
  final NetworkLogBody? body;
  final String emptyBodyText;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _KeyValueSection(
          title: 'Headers',
          values: headers,
          emptyText: 'No headers captured.',
        ),
        _BodyView(body: body, emptyText: emptyBodyText),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
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

class _KeyValueSection extends StatelessWidget {
  const _KeyValueSection({
    required this.title,
    required this.values,
    this.emptyText = '–',
  });

  final String title;
  final Map<String, String> values;
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
        _SectionTitle(title),
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
  const _BodyView({required this.body, required this.emptyText});

  final NetworkLogBody? body;
  final String emptyText;

  static String _pretty(NetworkLogBody body) {
    if (body.kind != NetworkBodyKind.json || body.isTruncated) {
      return body.content;
    }
    try {
      return const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(body.content));
    } on FormatException {
      return body.content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    if (body == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const _SectionTitle('Body'), Text(emptyText)],
      );
    }
    final text = _pretty(body);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          'Body (${body.kind.name})',
          trailing: IconButton(
            tooltip: 'Copy body',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          ),
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
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
