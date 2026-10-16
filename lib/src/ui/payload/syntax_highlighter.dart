import 'package:flutter/painting.dart';

import '../theme/inspector_theme.dart';

/// Languages the inspector can highlight.
enum SyntaxLanguage {
  /// JSON.
  json,

  /// XML and HTML.
  markup,

  /// GraphQL documents.
  graphql,

  /// `application/x-www-form-urlencoded`.
  form,

  /// No highlighting (redacted values are still marked).
  plain,
}

final RegExp _jsonToken = RegExp(
  r'("(?:[^"\\]|\\.)*")(\s*:)?|(-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?)|\b(true|false|null)\b|([{}\[\],:])',
);
final RegExp _markupToken = RegExp(r'<!--[\s\S]*?-->|<[^<>]+>');
final RegExp _tagStart = RegExp(r'^(</?|<\?|<!)([\w:.\-]*)');
final RegExp _attribute = RegExp(r'''([\w:.\-]+)(\s*=\s*)("[^"]*"|'[^']*')''');
final RegExp _graphqlToken = RegExp(
  r'(#[^\n]*)|("""[\s\S]*?"""|"(?:[^"\\]|\\.)*")|(\$[_A-Za-z]\w*)|\b(query|mutation|subscription|fragment|on|true|false|null)\b|(-?\d+(?:\.\d+)?)|([_A-Za-z]\w*)(?=\s*[:(])|([{}()\[\]:!=,@])',
);
final RegExp _formToken = RegExp(r'([^&=]+)(=)([^&]*)|(&)');

/// Splits [text] into styled spans for [language].
///
/// Occurrences of [mask] are always marked as redacted.
List<TextSpan> highlight(
  String text,
  SyntaxLanguage language,
  SyntaxPalette palette, {
  String mask = '***',
}) {
  final spans = <TextSpan>[];

  void emit(String value, Color color, {FontWeight? weight}) {
    if (value.isEmpty) return;
    final style = TextStyle(color: color, fontWeight: weight);
    if (mask.isEmpty || !value.contains(mask)) {
      spans.add(TextSpan(text: value, style: style));
      return;
    }
    final parts = value.split(mask);
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(TextSpan(text: parts[i], style: style));
      }
      if (i < parts.length - 1) {
        spans.add(
          TextSpan(
            text: mask,
            style: TextStyle(
              color: palette.redacted,
              backgroundColor: palette.redactedBackground,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
    }
  }

  void tokens(
    RegExp pattern,
    void Function(Match match) onMatch,
  ) {
    var last = 0;
    for (final match in pattern.allMatches(text)) {
      emit(text.substring(last, match.start), palette.plain);
      onMatch(match);
      last = match.end;
    }
    emit(text.substring(last), palette.plain);
  }

  switch (language) {
    case SyntaxLanguage.plain:
      emit(text, palette.plain);
    case SyntaxLanguage.json:
      tokens(_jsonToken, (m) {
        if (m.group(1) != null) {
          final isKey = m.group(2) != null;
          emit(m.group(1)!, isKey ? palette.key : palette.string,
              weight: isKey ? FontWeight.w600 : null);
          if (isKey) emit(m.group(2)!, palette.punctuation);
        } else if (m.group(3) != null) {
          emit(m.group(3)!, palette.number);
        } else if (m.group(4) != null) {
          emit(m.group(4)!, palette.keyword, weight: FontWeight.w600);
        } else {
          emit(m.group(5)!, palette.punctuation);
        }
      });
    case SyntaxLanguage.markup:
      tokens(_markupToken, (m) => _markupTag(m.group(0)!, palette, emit));
    case SyntaxLanguage.graphql:
      tokens(_graphqlToken, (m) {
        if (m.group(1) != null) {
          emit(m.group(1)!, palette.comment);
        } else if (m.group(2) != null) {
          emit(m.group(2)!, palette.string);
        } else if (m.group(3) != null) {
          emit(m.group(3)!, palette.attribute);
        } else if (m.group(4) != null) {
          emit(m.group(4)!, palette.keyword, weight: FontWeight.w600);
        } else if (m.group(5) != null) {
          emit(m.group(5)!, palette.number);
        } else if (m.group(6) != null) {
          emit(m.group(6)!, palette.key);
        } else {
          emit(m.group(7)!, palette.punctuation);
        }
      });
    case SyntaxLanguage.form:
      tokens(_formToken, (m) {
        if (m.group(4) != null) {
          emit(m.group(4)!, palette.punctuation);
          return;
        }
        emit(m.group(1)!, palette.key, weight: FontWeight.w600);
        emit(m.group(2)!, palette.punctuation);
        emit(m.group(3)!, palette.string);
      });
  }
  return spans;
}

void _markupTag(
  String tag,
  SyntaxPalette palette,
  void Function(String, Color, {FontWeight? weight}) emit,
) {
  if (tag.startsWith('<!--')) {
    emit(tag, palette.comment);
    return;
  }
  final start = _tagStart.firstMatch(tag);
  if (start == null) {
    emit(tag, palette.punctuation);
    return;
  }
  emit(start.group(1)!, palette.punctuation);
  emit(start.group(2)!, palette.tag, weight: FontWeight.w600);
  final rest = tag.substring(start.end);
  var last = 0;
  for (final m in _attribute.allMatches(rest)) {
    emit(rest.substring(last, m.start), palette.punctuation);
    emit(m.group(1)!, palette.attribute);
    emit(m.group(2)!, palette.punctuation);
    emit(m.group(3)!, palette.string);
    last = m.end;
  }
  emit(rest.substring(last), palette.punctuation);
}
