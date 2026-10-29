import 'dart:convert';
import 'dart:typed_data';

import '../core/contracts/payload_decoder.dart';
import '../core/entities/network_log_body.dart';
import '../core/entities/payload_format.dart';
import 'log_redactor.dart';
import 'payload_format_detector.dart';

/// Turns arbitrary request and response payloads into redacted, size-bounded
/// [NetworkLogBody] snapshots.
///
/// The pipeline for each payload is: detect the format (declared content
/// type first, content sniffing as a fallback), let registered
/// [PayloadDecoder]s decode it, redact by key (structures) or by pattern
/// (text, form, XML/HTML), then serialize and truncate.
///
/// The original payload is never mutated, streams are never listened to and
/// binary data is never decoded into text unless a decoder asks for it.
class BodyCapture {
  /// Creates a capture policy keeping at most [maxSize] characters per body.
  const BodyCapture({
    required LogRedactor redactor,
    required this.maxSize,
    this.decoders = const [],
  }) : _redactor = redactor;

  /// Bodies longer than this many characters are not parsed; they fall back
  /// to pattern-based redaction.
  static const int parseLimit = 1024 * 1024;

  /// The maximum number of characters kept per body.
  final int maxSize;

  /// Custom decoders, tried in order before the built-in handling.
  final List<PayloadDecoder> decoders;

  final LogRedactor _redactor;

  /// Captures [data] of any type, or returns `null` when there is no body.
  ///
  /// [context] describes where the payload was seen; its content type is
  /// used when [contentType] is omitted.
  NetworkLogBody? capture(
    Object? data, {
    String? contentType,
    PayloadContext? context,
  }) {
    final ctx = _context(context, contentType);
    if (data == null) return null;
    if (data is String) {
      if (data.isEmpty) return null;
      return _decodeText(data, ctx) ??
          _fromText(
              data,
              ctx,
              PayloadFormatDetector.fromContentType(
                ctx.contentType,
              ));
    }
    if (data is List<int>) return fromBytes(data, context: ctx);
    if (data is ByteBuffer) return _binary(data.lengthInBytes, ctx);
    if (data is TypedData) return _binary(data.lengthInBytes, ctx);
    if (data is Stream) return stream();
    if (data is num || data is bool) {
      return _truncate(NetworkBodyKind.text, '$data', PayloadFormat.text, ctx);
    }
    if (data is Map || data is Iterable) {
      return _fromStructure(
          _redactor.redactValue(data), PayloadFormat.json, ctx);
    }
    return _fromObject(data, ctx);
  }

  /// Captures raw [bytes]. Set [isComplete] to `false` when [bytes] is only a
  /// prefix of the payload; the result is then marked as truncated and
  /// decoders are not run.
  NetworkLogBody? fromBytes(
    List<int> bytes, {
    String? contentType,
    bool isComplete = true,
    PayloadContext? context,
  }) {
    if (bytes.isEmpty) return null;
    final ctx = _context(context, contentType);
    if (isComplete) {
      final decoded = _decode(bytes, ctx);
      if (decoded != null) return decoded;
    }
    final declared = PayloadFormatDetector.fromContentType(ctx.contentType);
    if (declared == PayloadFormat.protobuf) {
      return NetworkLogBody(
        kind: NetworkBodyKind.binary,
        content: '<protobuf, ${bytes.length} bytes; '
            'register a ProtobufPayloadDecoder to inspect>',
        format: PayloadFormat.protobuf,
        contentType: ctx.contentType,
      );
    }
    if (declared == PayloadFormat.binary ||
        (declared == null && (ctx.contentType != null || !isComplete))) {
      return _binary(bytes.length, ctx);
    }
    final String text;
    if (declared == null) {
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        return _binary(bytes.length, ctx);
      }
      if (_hasControlCharacters(text)) return _binary(bytes.length, ctx);
    } else {
      text = utf8.decode(bytes, allowMalformed: true);
    }
    final body = _fromText(text, ctx, declared);
    if (isComplete || body.isTruncated) return body;
    return NetworkLogBody(
      kind: body.kind,
      content: body.content,
      isTruncated: true,
      format: body.format,
      contentType: body.contentType,
    );
  }

  /// Describes a multipart form without reading any file contents.
  ///
  /// Text fields are masked by name; other field values are redacted by
  /// content, so JSON fields (such as a GraphQL `operations` field) are
  /// redacted by key.
  NetworkLogBody multipart({
    required Iterable<MapEntry<String, String>> fields,
    required Iterable<MultipartFileInfo> files,
    String? contentType,
  }) {
    final description = {
      'fields': [
        for (final field in fields)
          {
            'name': field.key,
            'value': _redactor.isSensitiveBodyKey(field.key)
                ? _redactor.mask
                : _redactor.redactString(field.value),
          },
      ],
      'files': [for (final file in files) file.toJson()],
    };
    return _truncate(
      NetworkBodyKind.multipart,
      jsonEncode(description),
      PayloadFormat.multipart,
      PayloadContext(contentType: contentType),
    );
  }

  /// A placeholder for a stream body that was intentionally not read.
  NetworkLogBody stream() => const NetworkLogBody(
        kind: NetworkBodyKind.stream,
        content: '<stream not captured>',
      );

  /// The size of [data] in bytes, when it can be measured cheaply.
  static int? sizeOf(Object? data) {
    if (data is String) {
      return data.length <= parseLimit ? utf8.encode(data).length : null;
    }
    if (data is List<int>) return data.length;
    if (data is TypedData) return data.lengthInBytes;
    if (data is ByteBuffer) return data.lengthInBytes;
    return null;
  }

  static PayloadContext _context(PayloadContext? context, String? type) {
    if (context == null) return PayloadContext(contentType: type);
    if (type == null || context.contentType != null) return context;
    return PayloadContext(
      contentType: type,
      url: context.url,
      direction: context.direction,
      protocol: context.protocol,
    );
  }

  NetworkLogBody? _decodeText(String text, PayloadContext ctx) {
    if (decoders.isEmpty || text.length > parseLimit) return null;
    return _decode(utf8.encode(text), ctx);
  }

  NetworkLogBody? _decode(List<int> bytes, PayloadContext ctx) {
    if (decoders.isEmpty || bytes.length > parseLimit) return null;
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    for (final decoder in decoders) {
      try {
        if (!decoder.canDecode(ctx)) continue;
        final value = decoder.decode(data, ctx);
        if (value == null) continue;
        if (value is String) {
          return _truncate(
            NetworkBodyKind.text,
            _redactor.redactText(value),
            decoder.format,
            ctx,
          );
        }
        return _fromStructure(
            _redactor.redactValue(value), decoder.format, ctx);
      } catch (_) {
        // A failing decoder falls back to the next one or built-in handling.
      }
    }
    return null;
  }

  NetworkLogBody _fromText(
    String text,
    PayloadContext ctx,
    PayloadFormat? declared,
  ) {
    final format = declared ?? PayloadFormatDetector.sniff(text);
    if (format == PayloadFormat.json && text.length <= parseLimit) {
      try {
        return _fromStructure(
          _redactor.redactValue(jsonDecode(text)),
          PayloadFormat.json,
          ctx,
        );
      } on FormatException {
        // Not valid JSON (or truncated); fall through to text redaction.
      }
    }
    final looksLikeJson =
        PayloadFormatDetector.sniff(text) == PayloadFormat.json;
    final redacted = switch (format) {
      PayloadFormat.xml || PayloadFormat.html => _redactor.redactMarkup(text),
      _ => _redactor.redactText(text),
    };
    final kind = format == PayloadFormat.json || looksLikeJson
        ? NetworkBodyKind.json
        : NetworkBodyKind.text;
    return _truncate(
      kind,
      redacted,
      looksLikeJson ? PayloadFormat.json : format,
      ctx,
    );
  }

  NetworkLogBody _fromStructure(
    Object? redacted,
    PayloadFormat format,
    PayloadContext ctx,
  ) =>
      _truncate(NetworkBodyKind.json, jsonEncode(redacted), format, ctx);

  NetworkLogBody _fromObject(Object data, PayloadContext ctx) {
    try {
      // Mirrors what HTTP clients send: objects are encoded via `toJson`.
      final structure = jsonDecode(jsonEncode(data));
      return _fromStructure(
        _redactor.redactValue(structure),
        PayloadFormat.json,
        ctx,
      );
    } catch (_) {
      return NetworkLogBody(
        kind: NetworkBodyKind.unsupported,
        content: '<${data.runtimeType}>',
        contentType: ctx.contentType,
      );
    }
  }

  NetworkLogBody _binary(int length, PayloadContext ctx) => NetworkLogBody(
        kind: NetworkBodyKind.binary,
        content: '<binary, $length bytes>',
        contentType: ctx.contentType,
      );

  NetworkLogBody _truncate(
    NetworkBodyKind kind,
    String content,
    PayloadFormat format,
    PayloadContext ctx,
  ) {
    if (content.length <= maxSize) {
      return NetworkLogBody(
        kind: kind,
        content: content,
        format: format,
        contentType: ctx.contentType,
      );
    }
    var end = maxSize;
    // Do not split a UTF-16 surrogate pair.
    if (end > 0 && _isHighSurrogate(content.codeUnitAt(end - 1))) end--;
    return NetworkLogBody(
      kind: kind,
      content: content.substring(0, end),
      isTruncated: true,
      format: format,
      contentType: ctx.contentType,
    );
  }

  /// Valid UTF-8 can still be binary (e.g. zero bytes); real text rarely
  /// contains control characters other than whitespace.
  static bool _hasControlCharacters(String text) {
    for (final unit in text.codeUnits) {
      if (unit < 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) {
        return true;
      }
    }
    return false;
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}

/// Metadata describing one file in a multipart request.
class MultipartFileInfo {
  /// Creates file metadata.
  const MultipartFileInfo({
    required this.field,
    this.filename,
    this.contentType,
    this.length,
  });

  /// The form field name.
  final String field;

  /// The file name, if provided.
  final String? filename;

  /// The declared content type, if any.
  final String? contentType;

  /// The file length in bytes, if known.
  final int? length;

  /// A JSON-compatible representation.
  Map<String, Object?> toJson() => {
        'field': field,
        'filename': filename,
        'contentType': contentType,
        'length': length,
      };
}
