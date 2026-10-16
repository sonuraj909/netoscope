import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/inspector_theme.dart';
import '../widgets/section_card.dart';
import 'syntax_highlighter.dart';

/// Above this many lines, code is rendered lazily, line by line.
const int lazyLineThreshold = 300;

/// A syntax-highlighted code block with line numbers and a wrap toggle.
class CodeBlock extends StatefulWidget {
  /// Creates a code block.
  const CodeBlock({
    super.key,
    required this.text,
    this.language = SyntaxLanguage.plain,
  });

  /// The code shown.
  final String text;

  /// How [text] is highlighted.
  final SyntaxLanguage language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _wrap = false;

  @override
  Widget build(BuildContext context) {
    final palette = SyntaxPalette.of(context);
    final mask = RedactionMaskScope.of(context);
    final lines = const LineSplitter().convert(widget.text);
    final theme = Theme.of(context);
    final lazy = lines.length > lazyLineThreshold;

    final Widget content;
    if (lazy) {
      content = _LazyLines(
        lines: lines,
        language: widget.language,
        palette: palette,
        mask: mask,
      );
    } else {
      final code = SelectableText.rich(
        TextSpan(
          children: highlight(
            widget.text,
            widget.language,
            palette,
            mask: mask,
          ),
        ),
        style: codeTextStyle.copyWith(color: palette.plain),
      );
      content = _wrap
          ? Padding(padding: const EdgeInsets.all(12), child: code)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Gutter(count: lines.length, palette: palette),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(10, 12, 40, 12),
                    child: code,
                  ),
                ),
              ],
            );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Stack(
        children: [
          content,
          if (!lazy)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: _wrap ? 'Unwrap lines' : 'Wrap lines',
                color: palette.lineNumber,
                icon: Icon(_wrap ? Icons.wrap_text : Icons.notes),
                onPressed: () => setState(() => _wrap = !_wrap),
              ),
            ),
        ],
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({required this.count, required this.palette});

  final int count;
  final SyntaxPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: palette.lineNumber.withAlpha(60)),
        ),
      ),
      child: Text(
        [for (var i = 1; i <= count; i++) '$i'].join('\n'),
        textAlign: TextAlign.right,
        style: codeTextStyle.copyWith(color: palette.lineNumber),
      ),
    );
  }
}

class _LazyLines extends StatelessWidget {
  const _LazyLines({
    required this.lines,
    required this.language,
    required this.palette,
    required this.mask,
  });

  final List<String> lines;
  final SyntaxLanguage language;
  final SyntaxPalette palette;
  final String mask;

  @override
  Widget build(BuildContext context) {
    final digits = '${lines.length}'.length;
    final style = codeTextStyle.copyWith(color: palette.plain);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Scrollbar(
        child: ListView.builder(
          key: const ValueKey('netoscope-lazy-body'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: lines.length,
          itemExtent: 19,
          itemBuilder: (context, index) => Row(
            children: [
              SizedBox(
                width: digits * 8.0 + 20,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.right,
                  style: codeTextStyle.copyWith(color: palette.lineNumber),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: highlight(
                      lines[index],
                      language,
                      palette,
                      mask: mask,
                    ),
                  ),
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
