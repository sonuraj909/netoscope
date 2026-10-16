import 'dart:convert';
import 'dart:developer' as developer;

import '../../config/network_logger_config.dart';
import '../../core/contracts/network_log_sink.dart';
import '../../core/entities/graphql_details.dart';
import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/protocol_details.dart';
import '../../core/entities/webhook_details.dart';

/// Writes already-redacted entries to the developer console.
///
/// By default output goes through `dart:developer`'s `log`, which appears in
/// IDE debug consoles and DevTools. Pass [output] to redirect it, for example
/// to Flutter's `debugPrint`.
///
/// Set [colors] to add ANSI colors (status by outcome, method, tags and
/// section titles). Only enable it for consoles that render ANSI escapes.
class ConsoleNetworkLogSink implements NetworkLogSink {
  /// Creates a console sink.
  ConsoleNetworkLogSink({
    this.level = ConsoleLogLevel.summary,
    this.slowRequestThreshold = const Duration(seconds: 3),
    this.colors = false,
    void Function(String message)? output,
  }) : _output = output ?? _developerLog;

  /// Whether ANSI color codes are added.
  final bool colors;

  /// How much detail is written.
  final ConsoleLogLevel level;

  /// Calls at least this slow are tagged `[SLOW]`.
  final Duration slowRequestThreshold;

  final void Function(String message) _output;

  static void _developerLog(String message) =>
      developer.log(message, name: 'netoscope');

  @override
  void write(NetworkLogEntry entry) {
    if (level == ConsoleLogLevel.none) return;
    _output(format(entry));
  }

  /// Formats [entry] according to [level].
  String format(NetworkLogEntry entry) {
    final buffer = StringBuffer(_summary(entry));
    final error = entry.error;
    if (error != null) {
      buffer.write(
        '\n  ${_paint('error: ${error.type.name}: ${error.message}', _red)}',
      );
    }
    if (level == ConsoleLogLevel.verbose) {
      final sections = <(String, List<String>)>[
        if (entry.requestHeaders.isNotEmpty)
          ('Request headers', _headerLines(entry.requestHeaders)),
        if (entry.requestBody case final NetworkLogBody body)
          ('Request body · ${body.format.label}', _bodyLines(body)),
        if (entry.responseHeaders.isNotEmpty)
          ('Response headers', _headerLines(entry.responseHeaders)),
        if (entry.responseBody case final NetworkLogBody body)
          ('Response body · ${body.format.label}', _bodyLines(body)),
        for (final details in entry.details)
          (details.label, _headerLines(details.describe())),
      ];
      for (final (index, (title, lines)) in sections.indexed) {
        buffer.write('\n  ${index == 0 ? '┌' : '├'}─ ${_paint(title, _bold)}');
        for (final line in lines) {
          buffer.write('\n  │  $line');
        }
      }
      if (sections.isNotEmpty) buffer.write('\n  └─');
    }
    return buffer.toString();
  }

  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _red = '\x1B[31m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _cyan = '\x1B[36m';
  static const _magenta = '\x1B[35m';

  String _paint(String text, String code) =>
      colors ? '$code$text$_reset' : text;

  String _statusColor(NetworkLogEntry entry) => switch (entry.outcome) {
        NetworkLogOutcome.success => _green,
        NetworkLogOutcome.httpError =>
          (entry.statusCode ?? 0) >= 500 ? _red : _yellow,
        NetworkLogOutcome.failure => _red,
        NetworkLogOutcome.cancelled => _magenta,
      };

  String _summary(NetworkLogEntry entry) {
    final duration = entry.duration;
    final time = duration == null ? '' : ' (${duration.inMilliseconds} ms)';
    final method = _paint(entry.method, _bold);
    final tags = _tags(entry);
    final paintedTags = tags.isEmpty ? '' : _paint(tags, _cyan);
    switch (entry.kind) {
      case NetworkEventKind.message:
        final arrow = entry.direction == MessageDirection.outgoing ? '↑' : '↓';
        final body = entry.messageBody;
        final what = body == null ? '' : ' (${body.format.label})';
        return '$method $arrow ${entry.url}$what$paintedTags';
      case NetworkEventKind.connection:
        final stage = _paint(
          entry.lifecycle?.name ?? 'event',
          _statusColor(entry),
        );
        return '$method $stage ${entry.url}$time$paintedTags';
      case NetworkEventKind.exchange:
        final status = _paint(
          entry.statusCode?.toString() ?? entry.outcome.name.toUpperCase(),
          _statusColor(entry),
        );
        final slow = entry.isSlower(slowRequestThreshold)
            ? _paint(' [SLOW]', _yellow)
            : '';
        return '$method ${entry.url} → $status$time$slow$paintedTags';
    }
  }

  static String _tags(NetworkLogEntry entry) {
    final tags = <String>[
      for (final details in entry.details)
        switch (details) {
          GraphQLDetails(:final summary, :final errors) => errors.isEmpty
              ? 'GraphQL $summary'
              : 'GraphQL $summary, ${errors.length} errors',
          GrpcDetails(:final statusName) =>
            statusName == null ? 'gRPC' : 'gRPC $statusName',
          WebhookDetails(:final outcome) => 'webhook ${outcome.name}',
          SseDetails(:final eventType) => 'event: $eventType',
          MqttDetails(:final topic) when topic != null => 'topic: $topic',
          _ => '',
        },
    ]..removeWhere((tag) => tag.isEmpty);
    return tags.isEmpty ? '' : ' [${tags.join('; ')}]';
  }

  List<String> _headerLines(Map<String, String> headers) => [
        for (final header in headers.entries)
          '${_paint(header.key, _cyan)}: ${header.value}',
      ];

  static List<String> _bodyLines(NetworkLogBody body) {
    var text = body.content;
    if (body.kind == NetworkBodyKind.json && !body.isTruncated) {
      try {
        text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
      } on FormatException {
        // Keep the captured text.
      }
    }
    return [
      ...const LineSplitter().convert(text),
      if (body.isTruncated) '…(truncated)',
    ];
  }
}
