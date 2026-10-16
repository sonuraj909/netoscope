import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/src/ui/payload/syntax_highlighter.dart';
import 'package:netoscope/src/ui/theme/inspector_theme.dart';

void main() {
  const palette = SyntaxPalette(
    background: Color(0xFF000000),
    plain: Color(0xFF000001),
    key: Color(0xFF000002),
    string: Color(0xFF000003),
    number: Color(0xFF000004),
    keyword: Color(0xFF000005),
    punctuation: Color(0xFF000006),
    tag: Color(0xFF000007),
    attribute: Color(0xFF000008),
    comment: Color(0xFF000009),
    redacted: Color(0xFF00000A),
    redactedBackground: Color(0xFF00000B),
    lineNumber: Color(0xFF00000C),
  );

  Color? colorOf(List<TextSpan> spans, String text) =>
      spans.firstWhere((s) => s.text == text).style?.color;

  test('JSON keys, strings, numbers, keywords and redacted values', () {
    const source = '{"name": "Ada", "age": 36, "admin": true, "token": "***"}';
    final spans = highlight(source, SyntaxLanguage.json, palette);

    expect(spans.map((s) => s.text).join(), source, reason: 'lossless');
    expect(colorOf(spans, '"name"'), palette.key);
    expect(colorOf(spans, '"Ada"'), palette.string);
    expect(colorOf(spans, '36'), palette.number);
    expect(colorOf(spans, 'true'), palette.keyword);
    expect(colorOf(spans, '***'), palette.redacted);
  });

  test('markup tags, attributes and text', () {
    const source = '<user id="7"><!-- note --><name>Ada</name></user>';
    final spans = highlight(source, SyntaxLanguage.markup, palette);

    expect(spans.map((s) => s.text).join(), source);
    expect(colorOf(spans, 'user'), palette.tag);
    expect(colorOf(spans, 'id'), palette.attribute);
    expect(colorOf(spans, '"7"'), palette.string);
    expect(colorOf(spans, '<!-- note -->'), palette.comment);
    expect(colorOf(spans, 'Ada'), palette.plain);
  });

  test('GraphQL keywords, variables and fields', () {
    const source = r'query Get($id: ID!) { user(id: $id) { name } }';
    final spans = highlight(source, SyntaxLanguage.graphql, palette);

    expect(spans.map((s) => s.text).join(), source);
    expect(colorOf(spans, 'query'), palette.keyword);
    expect(colorOf(spans, r'$id'), palette.attribute);
    expect(colorOf(spans, 'user'), palette.key);
  });

  test('form pairs and custom masks', () {
    final spans = highlight(
      'user=ada&pin=[hidden]',
      SyntaxLanguage.form,
      palette,
      mask: '[hidden]',
    );
    expect(colorOf(spans, 'user'), palette.key);
    expect(colorOf(spans, 'ada'), palette.string);
    expect(colorOf(spans, '[hidden]'), palette.redacted);
  });
}
