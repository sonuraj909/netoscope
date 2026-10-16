import 'dart:convert';
import 'dart:typed_data';

import '../core/entities/network_log_body.dart';
import 'log_redactor.dart';

/// Turns arbitrary request and response payloads into redacted, size-bounded
/// [NetworkLogBody] snapshots.
///
/// The original payload is never mutated, streams are never listened to and
/// binary data is never decoded into text.
class BodyCapture {
  /// Creates a capture policy keeping at most [maxSize] characters per body.
  const BodyCapture({required LogRedactor redactor, required this.maxSize})
      : _redactor = redactor;

  /// Bodies longer than this many characters are not parsed as JSON; they
  /// fall back to pattern-based redaction.
  static const int parseLimit = 1024 * 1024;

  /// The maximum number of characters kept per body.
  final int maxSize;

  final LogRedactor _redactor;

  /// Captures [data] of any type, or returns `null` when there is no body.
  NetworkLogBody? capture(Object? data, {String? contentType}) {
    if (data == null) return null;
    if (data is String) {
      return data.isEmpty ? null : _fromString(data, contentType);
    }
    if (data is List<int>) return fromBytes(data, contentType: contentType);
    if (data is ByteBuffer) return _binary(data.lengthInBytes);
    if (data is TypedData) return _binary(data.lengthInBytes);
    if (data is Stream) return stream();
    if (data is num || data is bool) {
      return _truncate(NetworkBodyKind.text, '$data');
    }
    if (data is Map || data is Iterable) {
      return _fromStructure(_redactor.redactValue(data));
    }
    return _fromObject(data);
  }

  /// Captures raw [bytes]. Set [isComplete] to `false` when [bytes] is only a
  /// prefix of the payload; the result is then marked as truncated.
  NetworkLogBody? fromBytes(
    List<int> bytes, {
    String? contentType,
    bool isComplete = true,
  }) {
    if (bytes.isEmpty) return null;
    if (!_isTextual(contentType)) {
      if (contentType != null || !isComplete) return _binary(bytes.length);
      try {
        final text = utf8.decode(bytes);
        if (_hasControlCharacters(text)) return _binary(bytes.length);
        return _fromString(text, contentType);
      } on FormatException {
        return _binary(bytes.length);
      }
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final body = _fromString(text, contentType);
    if (isComplete || body.isTruncated) return body;
    return NetworkLogBody(
      kind: body.kind,
      content: body.content,
      isTruncated: true,
    );
  }

  /// Describes a multipart form without reading any file contents.
  NetworkLogBody multipart({
    required Iterable<MapEntry<String, String>> fields,
    required Iterable<MultipartFileInfo> files,
  }) {
    final description = {
      'fields': [
        for (final field in fields)
          {
            'name': field.key,
            'value': _redactor.isSensitiveKey(field.key)
                ? _redactor.mask
                : field.value,
          },
      ],
      'files': [for (final file in files) file.toJson()],
    };
    return _truncate(NetworkBodyKind.multipart, jsonEncode(description));
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

  NetworkLogBody _fromString(String text, String? contentType) {
    final trimmed = text.trimLeft();
    final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    final declaredJson = contentType?.toLowerCase().contains('json') ?? false;
    if ((looksLikeJson || declaredJson) && text.length <= parseLimit) {
      try {
        return _fromStructure(_redactor.redactValue(jsonDecode(text)));
      } on FormatException {
        // Not valid JSON (or truncated); fall through to text redaction.
      }
    }
    final kind = looksLikeJson ? NetworkBodyKind.json : NetworkBodyKind.text;
    return _truncate(kind, _redactor.redactText(text));
  }

  NetworkLogBody _fromStructure(Object? redacted) =>
      _truncate(NetworkBodyKind.json, jsonEncode(redacted));

  NetworkLogBody _fromObject(Object data) {
    try {
      // Mirrors what HTTP clients send: objects are encoded via `toJson`.
      final structure = jsonDecode(jsonEncode(data));
      return _fromStructure(_redactor.redactValue(structure));
    } catch (_) {
      return NetworkLogBody(
        kind: NetworkBodyKind.unsupported,
        content: '<${data.runtimeType}>',
      );
    }
  }

  NetworkLogBody _binary(int length) => NetworkLogBody(
        kind: NetworkBodyKind.binary,
        content: '<binary, $length bytes>',
      );

  NetworkLogBody _truncate(NetworkBodyKind kind, String content) {
    if (content.length <= maxSize) {
      return NetworkLogBody(kind: kind, content: content);
    }
    var end = maxSize;
    // Do not split a UTF-16 surrogate pair.
    if (end > 0 && _isHighSurrogate(content.codeUnitAt(end - 1))) end--;
    return NetworkLogBody(
      kind: kind,
      content: content.substring(0, end),
      isTruncated: true,
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

  static const List<String> _textualMarkers = [
    'json',
    'text/',
    'xml',
    'x-www-form-urlencoded',
    'javascript',
    'graphql',
    'html',
  ];

  static bool _isTextual(String? contentType) {
    if (contentType == null) return false;
    final lower = contentType.toLowerCase();
    return _textualMarkers.any(lower.contains);
  }
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
