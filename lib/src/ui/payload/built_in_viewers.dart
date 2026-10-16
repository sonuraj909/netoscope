import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/network_log_body.dart';
import '../../core/entities/payload_format.dart';
import '../theme/inspector_theme.dart';
import '../widgets/section_card.dart';
import 'code_block.dart';
import 'json_tree_view.dart';
import 'payload_formatting.dart';
import 'payload_viewer.dart';
import 'syntax_highlighter.dart';

/// The built-in viewers, tried after any custom ones.
const List<PayloadViewer> builtInPayloadViewers = [
  JsonPayloadViewer(),
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

/// The highlighting language for a body.
SyntaxLanguage languageFor(NetworkLogBody body) {
  if (body.kind == NetworkBodyKind.json) return SyntaxLanguage.json;
  final format = body.format;
  if (format == PayloadFormat.xml || format == PayloadFormat.html) {
    return SyntaxLanguage.markup;
  }
  if (format == PayloadFormat.form) return SyntaxLanguage.form;
  return SyntaxLanguage.plain;
}

/// JSON with a Pretty (highlighted) and a Tree (collapsible) view.
class JsonPayloadViewer extends PayloadViewer {
  /// Creates the viewer.
  const JsonPayloadViewer();

  @override
  bool canView(NetworkLogBody body) => body.kind == NetworkBodyKind.json;

  @override
  Widget build(BuildContext context, NetworkLogBody body) =>
      _JsonBody(body: body);
}

/// XML, HTML, form-encoded and plain text, highlighted where possible.
class TextPayloadViewer extends PayloadViewer {
  /// Creates the viewer.
  const TextPayloadViewer();

  @override
  bool canView(NetworkLogBody body) => true;

  @override
  Widget build(BuildContext context, NetworkLogBody body) =>
      _FormattedCode(body: body);
}

/// Form-encoded bodies as a table, with the raw text below.
class FormPayloadViewer extends PayloadViewer {
  /// Creates the viewer.
  const FormPayloadViewer();

  @override
  bool canView(NetworkLogBody body) =>
      body.format == PayloadFormat.form && !body.isTruncated;

  @override
  Widget build(BuildContext context, NetworkLogBody body) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyValueTable(rows: parseForm(body.content), monospaceValues: true),
          const SizedBox(height: 10),
          _FormattedCode(body: body),
        ],
      );
}

/// Multipart fields and file metadata as tables.
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
      return _FormattedCode(body: body);
    }
    if (parsed is! Map) return _FormattedCode(body: body);
    final fields = parsed['fields'];
    final files = parsed['files'];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Fields', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        KeyValueTable(
          rows: [
            if (fields is List)
              for (final field in fields.whereType<Map<Object?, Object?>>())
                MapEntry('${field['name']}', '${field['value']}'),
          ],
          emptyText: 'No fields.',
        ),
        const SizedBox(height: 12),
        Text('Files', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        KeyValueTable(
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
    final icon = switch (body.kind) {
      NetworkBodyKind.stream => Icons.stream,
      NetworkBodyKind.unsupported => Icons.help_outline,
      _ => Icons.memory_outlined,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SyntaxPalette.of(context).background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                body.content,
                style: codeTextStyle.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _JsonMode { pretty, tree }

/// JSON larger than this is not offered as a tree.
const int _treeLimit = 256 * 1024;

class _JsonBody extends StatefulWidget {
  const _JsonBody({required this.body});

  final NetworkLogBody body;

  @override
  State<_JsonBody> createState() => _JsonBodyState();
}

class _JsonBodyState extends State<_JsonBody> {
  _JsonMode _mode = _JsonMode.pretty;
  Object? _decoded;
  bool _decodeFailed = false;

  bool get _treeAvailable =>
      !widget.body.isTruncated &&
      widget.body.content.length <= _treeLimit &&
      !_decodeFailed;

  void _showTree() {
    if (_decoded == null && !_decodeFailed) {
      try {
        _decoded = jsonDecode(widget.body.content);
      } on FormatException {
        _decodeFailed = true;
      }
    }
    setState(() => _mode = _decodeFailed ? _JsonMode.pretty : _JsonMode.tree);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_treeAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_JsonMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: _JsonMode.pretty,
                    label: Text('Pretty'),
                    icon: Icon(Icons.data_object, size: 16),
                  ),
                  ButtonSegment(
                    value: _JsonMode.tree,
                    label: Text('Tree'),
                    icon: Icon(Icons.account_tree_outlined, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    selection.first == _JsonMode.tree
                        ? _showTree()
                        : setState(() => _mode = _JsonMode.pretty),
              ),
            ),
          ),
        if (_mode == _JsonMode.tree && _decoded != null)
          JsonTreeView(value: _decoded)
        else
          _FormattedCode(body: widget.body),
      ],
    );
  }
}

/// Formats a body (in the background when large) and shows it highlighted.
class _FormattedCode extends StatefulWidget {
  const _FormattedCode({required this.body});

  final NetworkLogBody body;

  @override
  State<_FormattedCode> createState() => _FormattedCodeState();
}

class _FormattedCodeState extends State<_FormattedCode> {
  String? _text;
  Future<String>? _pending;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(_FormattedCode oldWidget) {
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
    final text = _text;
    if (text == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    return CodeBlock(text: text, language: languageFor(widget.body));
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
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
