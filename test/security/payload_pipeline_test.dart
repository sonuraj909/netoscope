import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/security/body_capture.dart';
import 'package:netoscope/src/security/log_redactor.dart';
import 'package:netoscope/src/security/payload_format_detector.dart';

/// A toy "key=value;key=value" binary format standing in for MessagePack.
class _KvDecoder implements PayloadDecoder {
  static const kv = PayloadFormat('kv', label: 'Key/Value');
  int calls = 0;

  @override
  PayloadFormat get format => kv;

  @override
  bool canDecode(PayloadContext context) =>
      context.contentType == 'application/x-kv';

  @override
  Object? decode(Uint8List bytes, PayloadContext context) {
    calls++;
    return {
      for (final pair in utf8.decode(bytes).split(';'))
        pair.split('=').first: pair.split('=').last,
    };
  }
}

void main() {
  BodyCapture capture({List<PayloadDecoder> decoders = const []}) =>
      BodyCapture(redactor: LogRedactor(), maxSize: 10000, decoders: decoders);

  group('format detection', () {
    test('uses the declared content type first', () {
      final cases = {
        'application/json; charset=utf-8': PayloadFormat.json,
        'application/problem+json': PayloadFormat.json,
        'application/xml': PayloadFormat.xml,
        'application/atom+xml': PayloadFormat.xml,
        'text/html; charset=utf-8': PayloadFormat.html,
        'application/x-www-form-urlencoded': PayloadFormat.form,
        'multipart/form-data; boundary=x': PayloadFormat.multipart,
        'application/x-protobuf': PayloadFormat.protobuf,
        'application/grpc-web+proto': PayloadFormat.protobuf,
        'text/csv': PayloadFormat.text,
        'image/png': PayloadFormat.binary,
        'application/octet-stream': PayloadFormat.binary,
      };
      cases.forEach((type, format) {
        expect(PayloadFormatDetector.fromContentType(type), format,
            reason: type);
      });
      expect(PayloadFormatDetector.fromContentType('application/x-custom'),
          isNull);
    });

    test('sniffs undeclared text', () {
      expect(PayloadFormatDetector.sniff(' {"a":1}'), PayloadFormat.json);
      expect(PayloadFormatDetector.sniff('<?xml version="1.0"?><a/>'),
          PayloadFormat.xml);
      expect(PayloadFormatDetector.sniff('<note><to>A</to></note>'),
          PayloadFormat.xml);
      expect(PayloadFormatDetector.sniff('<!DOCTYPE html><html></html>'),
          PayloadFormat.html);
      expect(PayloadFormatDetector.sniff('a=1&b=two'), PayloadFormat.form);
      expect(PayloadFormatDetector.sniff('hello world'), PayloadFormat.text);
    });
  });

  group('redaction by format', () {
    test('XML elements and attributes', () {
      final body = capture().capture(
        '<login user="ada" token="t-1"><password>hunter2</password>'
        '<name>Ada</name></login>',
        contentType: 'application/xml',
      )!;
      expect(body.format, PayloadFormat.xml);
      expect(body.kind, NetworkBodyKind.text);
      expect(body.content, isNot(contains('hunter2')));
      expect(body.content, isNot(contains('t-1')));
      expect(body.content, contains('<password>***</password>'));
      expect(body.content, contains('token="***"'));
      expect(body.content, contains('<name>Ada</name>'));
    });

    test('HTML form inputs named after secrets', () {
      final body = capture().capture(
        '<!DOCTYPE html><form><input type="hidden" name="csrf_token" '
        'value="abc123"><input name="q" value="flutter"></form>',
      )!;
      expect(body.format, PayloadFormat.html);
      expect(body.content, isNot(contains('abc123')));
      expect(body.content, contains('value="flutter"'));
    });

    test('form bodies keep their format', () {
      final body = capture().capture('user=ada&password=x')!;
      expect(body.format, PayloadFormat.form);
      expect(body.content, 'user=ada&password=***');
    });
  });

  group('decoders', () {
    test('a matching decoder produces a redacted structure', () {
      final decoder = _KvDecoder();
      final body = capture(decoders: [decoder]).fromBytes(
        utf8.encode('user=ada;api_key=secret'),
        contentType: 'application/x-kv',
      )!;
      expect(body.format.id, 'kv');
      expect(body.kind, NetworkBodyKind.json);
      expect(body.content, '{"user":"ada","api_key":"***"}');
    });

    test('non-matching, failing or null decoders fall back', () {
      final failing = _ThrowingDecoder();
      final body = capture(decoders: [failing, _KvDecoder()]).capture(
        'plain',
        contentType: 'text/plain',
      )!;
      expect(failing.calls, 1);
      expect(body.format, PayloadFormat.text);
      expect(body.content, 'plain');
    });

    test('decoders never see partial payloads', () {
      final decoder = _KvDecoder();
      capture(decoders: [decoder]).fromBytes(
        utf8.encode('a=b'),
        contentType: 'application/x-kv',
        isComplete: false,
      );
      expect(decoder.calls, 0);
    });

    test('protobuf without a decoder is reported, not decoded', () {
      final body = capture().fromBytes(
        [8, 150, 1],
        contentType: 'application/x-protobuf',
      )!;
      expect(body.format, PayloadFormat.protobuf);
      expect(body.kind, NetworkBodyKind.binary);
      expect(body.content, contains('register a ProtobufPayloadDecoder'));
    });
  });

  group('ProtobufPayloadDecoder', () {
    List<int> frame(List<int> data, {int flag = 0}) => [
          flag,
          (data.length >> 24) & 0xff,
          (data.length >> 16) & 0xff,
          (data.length >> 8) & 0xff,
          data.length & 0xff,
          ...data,
        ];

    final decoder = ProtobufPayloadDecoder(
      decode: (bytes, context) => {'bytes': bytes.length, 'password': 'p'},
    );

    test('decodes plain protobuf bodies with the supplied function', () {
      final body = capture(decoders: [decoder]).fromBytes(
        [1, 2, 3],
        contentType: 'application/x-protobuf',
      )!;
      expect(body.format, PayloadFormat.protobuf);
      expect(body.content, '{"bytes":3,"password":"***"}');
    });

    test('unframes gRPC bodies, skipping trailers and compressed frames', () {
      final body = capture(decoders: [decoder]).fromBytes(
        [
          ...frame([1, 2]),
          ...frame([9], flag: 1),
          ...frame(utf8.encode('grpc-status: 0'), flag: 0x80),
        ],
        contentType: 'application/grpc-web+proto',
      )!;
      expect(jsonDecode(body.content), [
        {'bytes': 2, 'password': '***'},
        '<compressed message, 1 bytes>',
      ]);
    });

    test('ignores malformed frames', () {
      final body = capture(decoders: [decoder]).fromBytes(
        [0, 0, 0, 0, 9, 1],
        contentType: 'application/grpc',
      )!;
      expect(body.kind, NetworkBodyKind.binary);
    });
  });
}

class _ThrowingDecoder implements PayloadDecoder {
  int calls = 0;

  @override
  PayloadFormat get format => PayloadFormat.text;

  @override
  bool canDecode(PayloadContext context) => true;

  @override
  Object? decode(Uint8List bytes, PayloadContext context) {
    calls++;
    throw const FormatException('broken');
  }
}
