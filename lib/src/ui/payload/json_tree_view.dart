import 'package:flutter/material.dart';

import '../theme/inspector_theme.dart';
import '../widgets/section_card.dart';

/// At most this many children are shown per object or array.
const int _maxChildren = 200;

/// A collapsible JSON tree.
class JsonTreeView extends StatelessWidget {
  /// Creates a tree for a decoded JSON [value].
  const JsonTreeView({super.key, required this.value});

  /// The decoded JSON value.
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final palette = SyntaxPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _JsonNode(name: null, value: value, depth: 0),
      ),
    );
  }
}

class _JsonNode extends StatefulWidget {
  const _JsonNode({
    required this.name,
    required this.value,
    required this.depth,
    this.isIndex = false,
  });

  final String? name;
  final Object? value;
  final int depth;
  final bool isIndex;

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _expanded = widget.depth < 2;

  @override
  Widget build(BuildContext context) {
    final palette = SyntaxPalette.of(context);
    final mask = RedactionMaskScope.of(context);
    final value = widget.value;
    final style = codeTextStyle.copyWith(color: palette.plain);
    final name = widget.name;
    final label = name == null
        ? null
        : TextSpan(
            text: widget.isIndex ? '$name: ' : '"$name": ',
            style: TextStyle(
              color: widget.isIndex ? palette.number : palette.key,
              fontWeight: widget.isIndex ? null : FontWeight.w600,
            ),
          );

    if (value is! Map && value is! List) {
      return Padding(
        padding: const EdgeInsets.only(left: 20),
        child: SelectableText.rich(
          TextSpan(children: [
            if (label != null) label,
            _leaf(value, palette, mask)
          ]),
          style: style,
        ),
      );
    }

    final children = value is Map
        ? [
            for (final e in value.entries)
              (name: '${e.key}', value: e.value, isIndex: false),
          ]
        : [
            for (final (i, item) in (value as List).indexed)
              (name: '$i', value: item, isIndex: true),
          ];
    final open = value is Map ? '{' : '[';
    final close = value is Map ? '}' : ']';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: palette.punctuation,
              ),
              const SizedBox(width: 2),
              // Long keys wrap rather than overflow on narrow screens.
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (label != null) label,
                      TextSpan(
                        text: _expanded
                            ? open
                            : '$open … $close  ${children.length} '
                                '${children.length == 1 ? 'item' : 'items'}',
                        style: TextStyle(color: palette.punctuation),
                      ),
                    ],
                  ),
                  style: style,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: palette.punctuation.withAlpha(70)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final child in children.take(_maxChildren))
                  _JsonNode(
                    name: child.name,
                    value: child.value,
                    depth: widget.depth + 1,
                    isIndex: child.isIndex,
                  ),
                if (children.length > _maxChildren)
                  Padding(
                    padding: const EdgeInsets.only(left: 20, top: 2),
                    child: Text(
                      '… ${children.length - _maxChildren} more',
                      style: style.copyWith(color: palette.comment),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child:
                Text(close, style: style.copyWith(color: palette.punctuation)),
          ),
        ],
      ],
    );
  }

  static TextSpan _leaf(Object? value, SyntaxPalette palette, String mask) {
    if (value is String) {
      if (value == mask) {
        return TextSpan(
          text: '"$value"',
          style: TextStyle(
            color: palette.redacted,
            backgroundColor: palette.redactedBackground,
            fontWeight: FontWeight.w600,
          ),
        );
      }
      return TextSpan(
          text: '"$value"', style: TextStyle(color: palette.string));
    }
    if (value is num) {
      return TextSpan(text: '$value', style: TextStyle(color: palette.number));
    }
    return TextSpan(
      text: '$value',
      style: TextStyle(color: palette.keyword, fontWeight: FontWeight.w600),
    );
  }
}
