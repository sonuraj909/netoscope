import 'dart:convert';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';

/// A cURL command rebuilt from a recorded call.
class CurlCommand {
  /// Creates a command description.
  const CurlCommand({
    required this.command,
    required this.containsRedactedValues,
    required this.bodyOmitted,
  });

  /// The shell command, one option per line.
  final String command;

  /// Whether masked values (such as `***`) appear in the command. They must
  /// be replaced before the command can reproduce the original call.
  final bool containsRedactedValues;

  /// Whether the request had a body that could not be included (binary,
  /// streamed, truncated or unsupported).
  final bool bodyOmitted;
}

/// Headers that cURL computes itself.
const Set<String> _skippedHeaders = {'content-length', 'host'};

/// Rebuilds [entry] as a cURL command from its captured, already-redacted
/// data. Returns `null` for events that are not HTTP(S) exchanges.
CurlCommand? buildCurlCommand(
  NetworkLogEntry entry, {
  String redactionMask = '***',
}) {
  if (entry.kind != NetworkEventKind.exchange) return null;
  final scheme = entry.url.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  final body = entry.requestBody;
  final bodyArgs = <String>[];
  var omitted = false;
  var isMultipart = false;
  if (body != null) {
    if (body.isTruncated) {
      omitted = true;
    } else {
      switch (body.kind) {
        case NetworkBodyKind.json:
        case NetworkBodyKind.text:
          bodyArgs.add('--data-raw ${shellQuote(body.content)}');
        case NetworkBodyKind.multipart:
          final parts = _multipartArgs(body.content);
          if (parts == null) {
            omitted = true;
          } else {
            isMultipart = true;
            bodyArgs.addAll(parts);
          }
        case NetworkBodyKind.binary:
        case NetworkBodyKind.stream:
        case NetworkBodyKind.unsupported:
          omitted = true;
      }
    }
  }

  final args = <String>['curl'];
  final implied = bodyArgs.isEmpty ? 'GET' : 'POST';
  if (entry.method != implied) args.add('-X ${entry.method}');
  args.add(shellQuote(entry.url.toString()));
  for (final header in entry.requestHeaders.entries) {
    final name = header.key.toLowerCase();
    if (_skippedHeaders.contains(name)) continue;
    // cURL generates its own multipart boundary.
    if (isMultipart && name == 'content-type') continue;
    args.add('-H ${shellQuote('${header.key}: ${header.value}')}');
  }
  args.addAll(bodyArgs);

  final command = args.join(' \\\n  ');
  return CurlCommand(
    command: command,
    containsRedactedValues:
        redactionMask.isNotEmpty && command.contains(redactionMask),
    bodyOmitted: omitted,
  );
}

/// Quotes [value] for POSIX shells.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

List<String>? _multipartArgs(String content) {
  final Object? parsed;
  try {
    parsed = jsonDecode(content);
  } on FormatException {
    return null;
  }
  if (parsed is! Map) return null;
  final fields = parsed['fields'];
  final files = parsed['files'];
  return [
    if (fields is List)
      for (final field in fields.whereType<Map<Object?, Object?>>())
        '-F ${shellQuote('${field['name']}=${field['value']}')}',
    if (files is List)
      for (final file in files.whereType<Map<Object?, Object?>>())
        '-F ${shellQuote(_fileArg(file))}',
  ];
}

String _fileArg(Map<Object?, Object?> file) {
  final name = file['filename'] ?? 'file';
  final type = file['contentType'];
  return '${file['field']}=@$name${type == null ? '' : ';type=$type'}';
}
