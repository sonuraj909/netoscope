import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/security/body_capture.dart';
import 'package:netoscope/src/security/log_redactor.dart';

class _Credentials {
  _Credentials(this.user, this.password);
  final String user;
  final String password;
  Map<String, Object?> toJson() => {'user': user, 'password': password};
}

class _Opaque {
  @override
  String toString() => 'secret-from-toString';
}

void main() {
  final capture = BodyCapture(redactor: LogRedactor(), maxSize: 1000);

  test('returns null for missing or empty bodies', () {
    expect(capture.capture(null), isNull);
    expect(capture.capture(''), isNull);
    expect(capture.fromBytes(const []), isNull);
  });

  test('maps and lists become redacted JSON', () {
    final body = capture.capture({
      'email': 'a@b.dev',
      'password': 'x',
      'tags': [1, 2],
    })!;
    expect(body.kind, NetworkBodyKind.json);
    expect(body.content, '{"email":"a@b.dev","password":"***","tags":[1,2]}');
  });

  test('JSON strings are parsed and redacted structurally', () {
    final body = capture.capture('{"data":{"accessToken":"t"}}')!;
    expect(body.kind, NetworkBodyKind.json);
    expect(body.content, '{"data":{"accessToken":"***"}}');
  });

  test('plain and form-encoded text is redacted by pattern', () {
    final text = capture.capture('hello')!;
    expect(text.kind, NetworkBodyKind.text);
    expect(text.content, 'hello');

    final form = capture.capture(
      'user=ada&password=p',
      contentType: 'application/x-www-form-urlencoded',
    )!;
    expect(form.content, 'user=ada&password=***');
  });

  test('objects with toJson are serialized like HTTP clients do', () {
    expect(
      capture.capture(_Credentials('ada', 'pw'))!.content,
      '{"user":"ada","password":"***"}',
    );
  });

  test('unsupported objects never call toString', () {
    final body = capture.capture(_Opaque())!;
    expect(body.kind, NetworkBodyKind.unsupported);
    expect(body.content, '<_Opaque>');
  });

  group('binary data', () {
    test('typed data and declared binary content types are not decoded', () {
      expect(capture.capture(Uint8List(5))!.content, '<binary, 5 bytes>');
      final png = capture.fromBytes([1, 2, 3], contentType: 'image/png')!;
      expect(png.kind, NetworkBodyKind.binary);
      expect(png.content, '<binary, 3 bytes>');
    });

    test('undeclared bytes are decoded only when valid UTF-8', () {
      expect(
        capture.fromBytes(utf8.encode('{"pin":"1234"}'))!.content,
        '{"pin":"***"}',
      );
      expect(
        capture.fromBytes([0xff, 0xfe, 0x00])!.kind,
        NetworkBodyKind.binary,
      );
    });

    test('a textual prefix is marked as truncated', () {
      final body = capture.fromBytes(
        utf8.encode('{"token":"abc'),
        contentType: 'application/json',
        isComplete: false,
      )!;
      expect(body.isTruncated, isTrue);
      expect(body.content, '{"token":"***"');
    });
  });

  test('streams are described, never listened to', () {
    final controller = StreamController<List<int>>();
    final body = capture.capture(controller.stream)!;
    expect(body.kind, NetworkBodyKind.stream);
    expect(controller.hasListener, isFalse);
    controller.close();
  });

  test('multipart bodies list fields and file metadata only', () {
    final body = capture.multipart(
      fields: const [MapEntry('name', 'ada'), MapEntry('password', 'pw')],
      files: const [
        MultipartFileInfo(
          field: 'avatar',
          filename: 'a.png',
          contentType: 'image/png',
          length: 42,
        ),
      ],
    );
    expect(body.kind, NetworkBodyKind.multipart);
    expect(jsonDecode(body.content), {
      'fields': [
        {'name': 'name', 'value': 'ada'},
        {'name': 'password', 'value': '***'},
      ],
      'files': [
        {
          'field': 'avatar',
          'filename': 'a.png',
          'contentType': 'image/png',
          'length': 42,
        },
      ],
    });
  });

  group('truncation', () {
    test('cuts content at maxSize and flags it', () {
      final small = BodyCapture(redactor: LogRedactor(), maxSize: 5);
      final body = small.capture('abcdefgh')!;
      expect(body.content, 'abcde');
      expect(body.isTruncated, isTrue);
    });

    test('does not split surrogate pairs', () {
      final small = BodyCapture(redactor: LogRedactor(), maxSize: 2);
      expect(small.capture('a😀b')!.content, 'a');
    });

    test('maxSize 0 keeps only the kind', () {
      final none = BodyCapture(redactor: LogRedactor(), maxSize: 0);
      final body = none.capture({'a': 1})!;
      expect(body.content, isEmpty);
      expect(body.isTruncated, isTrue);
      expect(body.kind, NetworkBodyKind.json);
    });

    test('redaction happens before truncation', () {
      final small = BodyCapture(redactor: LogRedactor(), maxSize: 20);
      final body = small.capture({'password': 'a-very-long-secret-value'})!;
      expect(body.content, '{"password":"***"}');
      expect(body.isTruncated, isFalse);
    });

    test('bodies above the parse limit fall back to pattern redaction', () {
      final huge = '{"token":"abc","pad":"${'x' * BodyCapture.parseLimit}"}';
      final body = capture.capture(huge)!;
      expect(body.kind, NetworkBodyKind.json);
      expect(body.isTruncated, isTrue);
      expect(body.content, startsWith('{"token":"***","pad":"xxx'));
    });
  });

  test('sizeOf measures strings in UTF-8 bytes and binary by length', () {
    expect(BodyCapture.sizeOf('é'), 2);
    expect(BodyCapture.sizeOf(Uint8List(7)), 7);
    expect(BodyCapture.sizeOf({'a': 1}), isNull);
  });
}
