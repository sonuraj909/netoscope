import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/entities/network_log_body.dart';
import '../../core/entities/payload_format.dart';

/// Bodies at least this long are formatted in a background isolate.
const int backgroundFormatThreshold = 64 * 1024;

/// Whether [body] is large enough to be formatted in the background.
bool formatsInBackground(NetworkLogBody body) =>
    !kIsWeb && body.content.length >= backgroundFormatThreshold;

/// Pretty-prints [body] synchronously. Use for small bodies only.
String formatPayloadNow(NetworkLogBody body) =>
    _format(_FormatRequest(body.content, body.format.id, body.isTruncated));

/// Pretty-prints [body] in a background isolate.
Future<String> formatPayloadInBackground(NetworkLogBody body) => compute(
      _format,
      _FormatRequest(body.content, body.format.id, body.isTruncated),
    );

class _FormatRequest {
  const _FormatRequest(this.content, this.formatId, this.isTruncated);

  final String content;
  final String formatId;
  final bool isTruncated;
}

String _format(_FormatRequest request) {
  if (request.isTruncated) return request.content;
  if (request.formatId == PayloadFormat.xml.id) {
    return prettyXml(request.content);
  }
  final trimmed = request.content.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      return const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(request.content));
    } on FormatException {
      return request.content;
    }
  }
  return request.content;
}

final RegExp _xmlToken = RegExp(r'<[^>]+>|[^<]+');

/// Indents XML for readability. Text content is kept on the line of its
/// element. Falls back to [xml] unchanged if it does not look like markup.
String prettyXml(String xml) {
  final buffer = StringBuffer();
  var depth = 0;
  var lastWasText = false;
  for (final match in _xmlToken.allMatches(xml)) {
    final token = match.group(0)!;
    if (!token.startsWith('<')) {
      final text = token.trim();
      if (text.isEmpty) continue;
      buffer.write(text);
      lastWasText = true;
      continue;
    }
    final isClosing = token.startsWith('</');
    final isSelfContained = token.endsWith('/>') ||
        token.startsWith('<?') ||
        token.startsWith('<!');
    if (isClosing) {
      depth = depth > 0 ? depth - 1 : 0;
      if (!lastWasText) buffer.write('\n${'  ' * depth}');
      buffer.write(token);
    } else {
      if (buffer.isNotEmpty) buffer.write('\n${'  ' * depth}');
      buffer.write(token);
      if (!isSelfContained) depth++;
    }
    lastWasText = false;
  }
  return buffer.isEmpty ? xml : buffer.toString();
}

/// Splits a form-encoded body into decoded key/value pairs, keeping order
/// and duplicates.
List<MapEntry<String, String>> parseForm(String body) {
  String decode(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } on ArgumentError {
      return value;
    }
  }

  return [
    for (final pair in body.split('&'))
      if (pair.isNotEmpty)
        MapEntry(
          decode(
              pair.contains('=') ? pair.substring(0, pair.indexOf('=')) : pair),
          decode(
              pair.contains('=') ? pair.substring(pair.indexOf('=') + 1) : ''),
        ),
  ];
}
