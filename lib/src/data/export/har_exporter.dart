import 'dart:convert';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';

/// Exports HTTP exchanges as a HAR 1.2 document, readable by browser
/// DevTools, Charles, Proxyman, Postman and others.
///
/// Only exchanges with `http`/`https` URLs are included, oldest first.
/// Values are already redacted. Binary, streamed and unsupported bodies are
/// described in a comment instead of included.
String exportNetworkLogsAsHar(
  Iterable<NetworkLogEntry> entries, {
  String creatorVersion = '0.2.0',
}) {
  final calls = [
    for (final entry in entries)
      if (entry.kind == NetworkEventKind.exchange &&
          (entry.url.scheme == 'http' || entry.url.scheme == 'https'))
        entry,
  ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  return const JsonEncoder.withIndent('  ').convert({
    'log': {
      'version': '1.2',
      'creator': {'name': 'Netoscope', 'version': creatorVersion},
      'entries': [for (final entry in calls) _entry(entry)],
    },
  });
}

List<Map<String, String>> _headers(Map<String, String> headers) => [
      for (final e in headers.entries) {'name': e.key, 'value': e.value},
    ];

String? _header(Map<String, String> headers, String name) {
  for (final e in headers.entries) {
    if (e.key.toLowerCase() == name) return e.value;
  }
  return null;
}

bool _isTextual(NetworkLogBody body) =>
    body.kind == NetworkBodyKind.json ||
    body.kind == NetworkBodyKind.text ||
    body.kind == NetworkBodyKind.multipart;

Map<String, Object?> _entry(NetworkLogEntry entry) {
  final time = entry.duration?.inMicroseconds ?? 0;
  final request = entry.requestBody;
  final response = entry.responseBody;
  final comments = [
    if (entry.error != null) 'Error: ${entry.error!.message}',
    if (request != null && !_isTextual(request))
      'Request body: ${request.content}',
    if (response != null && !_isTextual(response))
      'Response body: ${response.content}',
    if ((request?.isTruncated ?? false) || (response?.isTruncated ?? false))
      'Bodies truncated by Netoscope',
  ];
  return {
    'startedDateTime': entry.timestamp.toUtc().toIso8601String(),
    'time': time / 1000,
    'request': {
      'method': entry.method,
      'url': entry.url.toString(),
      'httpVersion': 'HTTP/1.1',
      'cookies': const <Object>[],
      'headers': _headers(entry.requestHeaders),
      'queryString': [
        for (final param in entry.queryParameters.entries)
          for (final value in param.value) {'name': param.key, 'value': value},
      ],
      if (request != null && _isTextual(request))
        'postData': {
          'mimeType': request.contentType ??
              _header(entry.requestHeaders, 'content-type') ??
              (request.kind == NetworkBodyKind.json
                  ? 'application/json'
                  : 'text/plain'),
          'text': request.content,
        },
      'headersSize': -1,
      'bodySize': entry.requestSize ?? -1,
    },
    'response': {
      'status': entry.statusCode ?? 0,
      'statusText': '',
      'httpVersion': 'HTTP/1.1',
      'cookies': const <Object>[],
      'headers': _headers(entry.responseHeaders),
      'content': {
        'size': entry.responseSize ?? response?.content.length ?? 0,
        'mimeType': response?.contentType ??
            _header(entry.responseHeaders, 'content-type') ??
            'application/octet-stream',
        if (response != null && _isTextual(response)) 'text': response.content,
      },
      'redirectURL': _header(entry.responseHeaders, 'location') ?? '',
      'headersSize': -1,
      'bodySize': entry.responseSize ?? -1,
    },
    'cache': const <String, Object>{},
    'timings': {'send': 0, 'wait': time / 1000, 'receive': 0},
    if (comments.isNotEmpty) 'comment': comments.join('\n'),
    if (entry.tags.isNotEmpty) '_tags': entry.tags,
    '_netoscopeId': entry.id,
    '_protocol': entry.protocol.name,
  };
}
