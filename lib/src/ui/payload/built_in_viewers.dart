import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/network_log_body.dart';
import '../../core/entities/payload_format.dart';
import 'payload_formatting.dart';
import 'payload_viewer.dart';

/// The built-in viewers, tried after any custom ones.
const List<PayloadViewer> builtInPayloadViewers = [
  FormPayloadViewer(),
  MultipartPayloadViewer(),
  BinaryPayloadViewer(),
  TextPayloadViewer(),
];

/// Picks the first viewer in [custom] then [builtInPayloadViewers] that can
/// render [body].
PayloadViewer viewerFor(NetworkLogBody body, List<PayloadViewer> custom) {
  for (final viewer in [...custom, ...builtInPayloadViewers]) {
    try {
      if (viewer.canView(body)) return viewer;
    } catch (_) {
      // A misbehaving custom viewer must not break the inspector.
    }
  }
  return const TextPayloadViewer();
}

/// Shows JSON (pretty-printed), XML (indented), HTML and text. Long content
/// is rendered lazily, line by line.
class TextPayloadViewer extends PayloadViewer {
  /// Creates the viewer.
  const TextPayloadViewer();

  @override
  bool canView(NetworkLogBody body) => true;

  @override
  Widget build(BuildContext context, NetworkLogBody body) =>
      _FormattedText(body: body);
}

/// Shows form-encoded bodies as a table.
class FormPayloadViewer extends PayloadViewer {
  /// Creates the viewer.
  const FormPayloadViewer();

  @override
  bool canView(NetworkLogBody body) =>
      body.format == PayloadFormat.form && !body.isTruncated;

  @override
  Widget build(BuildContext context, NetworkLogBody body) =>
      _Table(rows: parseForm(body.content));
}

/// Shows multipart fields and file metadata as tables.
class MultipartPayloadViewer extends PayloadViewer {
  /// Creates the viewer.
  const MultipartPayloadViewer();

  @override
  bool canView(NetworkLogBody body) =>
      body.kind == NetworkBodyKind.multipart && !body.isTruncated;

  @override
  Widget build(BuildContext context, NetworkLogBody body) {
    final Object? parsed;
    try {
      parsed = jsonDecode(body.content);
    } on FormatException {
      return const TextPayloadViewer().build(context, body);
    }
    if (parsed is! Map) return const TextPayloadViewer().build(context, body);
    final fields = parsed['fields'];
    final files = parsed['files'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Table(
          rows: [
            if (fields is List)
              for (final field in fields.whereType<Map<Object?, Object?>>())
                MapEntry('${field['name']}', '${field['value']}'),
          ],
          emptyText: 'No fields.',
        ),
        const SizedBox(height: 12),
        Text('Files', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        _Table(
          rows: [
            if (files is List)
              for (final file in files.whereType<Map<Object?, Object?>>())
                MapEntry(
                  '${file['field']}',
                  '${file['filename'] ?? '(no name)'} · '
                      '${file['contentType'] ?? 'unknown type'} · '
                      '${file['length'] ?? '?'} bytes',
                ),
          ],
          emptyText: 'No files.',
        ),
      ],
    );
  }
}

/// Describes binary, stream and unsupported payloads.
class BinaryPayloadViewer extends PayloadViewer {
  /// Creates the viewer.
  const BinaryPayloadViewer();

  @override
  bool canView(NetworkLogBody body) =>
      body.kind == NetworkBodyKind.binary ||
      body.kind == NetworkBodyKind.stream ||
      body.kind == NetworkBodyKind.unsupported;

  @override
  Widget build(BuildContext context, NetworkLogBody body) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              body.kind == NetworkBodyKind.stream
                  ? Icons.stream
                  : Icons.memory_outlined,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(body.content)),
          ],
        ),
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows, this.emptyText = 'Empty.'});

  final List<MapEntry<String, String>> rows;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text(emptyText);
    final keyStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.key, style: keyStyle),
                SelectableText(row.value),
              ],
            ),
          ),
      ],
    );
  }
}

/// Above this many lines, text is shown in a lazily built list instead of a
/// single selectable text widget.
const int _lazyLineThreshold = 300;

class _FormattedText extends StatefulWidget {
  const _FormattedText({required this.body});

  final NetworkLogBody body;

  @override
  State<_FormattedText> createState() => _FormattedTextState();
}

class _FormattedTextState extends State<_FormattedText> {
  String? _text;
  Future<String>? _pending;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(_FormattedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) _prepare();
  }

  void _prepare() {
    final body = widget.body;
    if (!formatsInBackground(body)) {
      _text = formatPayloadNow(body);
      _pending = null;
      return;
    }
    _text = null;
    final pending = formatPayloadInBackground(body);
    _pending = pending;
    pending.then((text) {
      if (mounted && identical(_pending, pending)) {
        setState(() => _text = text);
      }
    }, onError: (Object _) {
      if (mounted && identical(_pending, pending)) {
        setState(() => _text = body.content);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const style = TextStyle(fontFamily: 'monospace', fontSize: 12);
    final text = _text;
    final Widget child;
    if (text == null) {
      child = const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    } else {
      final lines = const LineSplitter().convert(text);
      child = lines.length <= _lazyLineThreshold
          ? SelectableText(text, style: style)
          : SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: Scrollbar(
                child: ListView.builder(
                  key: const ValueKey('netoscope-lazy-body'),
                  itemCount: lines.length,
                  itemExtent: 16,
                  itemBuilder: (context, index) => Text(
                    lines[index],
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ),
            );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

/// Copies [text] and confirms with a snack bar.
Future<void> copyWithConfirmation(
  BuildContext context,
  String text,
  String message,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}
