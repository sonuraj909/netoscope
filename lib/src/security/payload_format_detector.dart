import '../core/entities/payload_format.dart';

/// Detects payload formats from content types, with content sniffing as a
/// fallback when no content type is declared.
abstract final class PayloadFormatDetector {
  /// The format implied by [contentType], or `null` when it is absent or
  /// not recognized.
  static PayloadFormat? fromContentType(String? contentType) {
    if (contentType == null) return null;
    final type = contentType.split(';').first.trim().toLowerCase();
    if (type.isEmpty) return null;
    if (type.startsWith('multipart/')) return PayloadFormat.multipart;
    if (type.contains('json')) return PayloadFormat.json;
    if (type == 'text/html' || type == 'application/xhtml+xml') {
      return PayloadFormat.html;
    }
    if (type.contains('xml')) return PayloadFormat.xml;
    if (type.contains('x-www-form-urlencoded')) return PayloadFormat.form;
    if (type == 'application/grpc-web-text' ||
        type.startsWith('application/grpc-web-text+')) {
      return PayloadFormat.text;
    }
    if (type.contains('protobuf') || type.startsWith('application/grpc')) {
      return PayloadFormat.protobuf;
    }
    if (type.startsWith('text/') ||
        type.contains('javascript') ||
        type.contains('ecmascript') ||
        type.contains('graphql') ||
        type.contains('yaml') ||
        type.contains('csv')) {
      return PayloadFormat.text;
    }
    if (_binaryPrefixes.any(type.startsWith) ||
        _binaryMarkers.any(type.contains)) {
      return PayloadFormat.binary;
    }
    return null;
  }

  static const List<String> _binaryPrefixes = [
    'image/',
    'audio/',
    'video/',
    'font/',
  ];

  static const List<String> _binaryMarkers = [
    'octet-stream',
    'pdf',
    'zip',
    'gzip',
    'wasm',
    'msgpack',
    'cbor',
    'avro',
  ];

  static final RegExp _formBody = RegExp(
    r'^[\w.\-\[\]%]+=[^&\s]*(?:&[\w.\-\[\]%]+=[^&\s]*)*$',
  );
  static final RegExp _markupStart = RegExp(r'^<(?:\?xml|[A-Za-z_!])');

  /// Guesses the format of [text] when no content type was declared.
  static PayloadFormat sniff(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return PayloadFormat.json;
    }
    if (_markupStart.hasMatch(trimmed)) {
      final head = trimmed
          .substring(0, trimmed.length < 64 ? trimmed.length : 64)
          .toLowerCase();
      return head.startsWith('<!doctype html') || head.startsWith('<html')
          ? PayloadFormat.html
          : PayloadFormat.xml;
    }
    if (trimmed.length <= 64 * 1024 && _formBody.hasMatch(trimmed.trim())) {
      return PayloadFormat.form;
    }
    return PayloadFormat.text;
  }
}
