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
class ConsoleNetworkLogSink implements NetworkLogSink {
  /// Creates a console sink.
  ConsoleNetworkLogSink({
    this.level = ConsoleLogLevel.summary,
    this.slowRequestThreshold = const Duration(seconds: 3),
    void Function(String message)? output,
  }) : _output = output ?? _developerLog;

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
      buffer.write('\n  error: ${error.type.name}: ${error.message}');
    }
    if (level == ConsoleLogLevel.verbose) {
      _writeHeaders(buffer, 'request headers', entry.requestHeaders);
      _writeBody(buffer, 'request body', entry.requestBody);
      _writeHeaders(buffer, 'response headers', entry.responseHeaders);
      _writeBody(buffer, 'response body', entry.responseBody);
      for (final details in entry.details) {
        _writeHeaders(buffer, details.label, details.describe());
      }
    }
    return buffer.toString();
  }

  String _summary(NetworkLogEntry entry) {
    final duration = entry.duration;
    final time = duration == null ? '' : ' (${duration.inMilliseconds} ms)';
    switch (entry.kind) {
      case NetworkEventKind.message:
        final arrow = entry.direction == MessageDirection.outgoing ? '↑' : '↓';
        final body = entry.messageBody;
        final what = body == null ? '' : ' (${body.format.label})';
        return '${entry.method} $arrow ${entry.url}$what${_tags(entry)}';
      case NetworkEventKind.connection:
        final stage = entry.lifecycle?.name ?? 'event';
        return '${entry.method} $stage ${entry.url}$time${_tags(entry)}';
      case NetworkEventKind.exchange:
        final status =
            entry.statusCode?.toString() ?? entry.outcome.name.toUpperCase();
        final slow = entry.isSlower(slowRequestThreshold) ? ' [SLOW]' : '';
        return '${entry.method} ${entry.url} → $status$time$slow${_tags(entry)}';
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

  static void _writeHeaders(
    StringBuffer buffer,
    String label,
    Map<String, String> headers,
  ) {
    if (headers.isEmpty) return;
    buffer.write('\n  $label:');
    for (final header in headers.entries) {
      buffer.write('\n    ${header.key}: ${header.value}');
    }
  }

  static void _writeBody(
      StringBuffer buffer, String label, NetworkLogBody? body) {
    if (body == null) return;
    final suffix = body.isTruncated ? ' …(truncated)' : '';
    buffer.write('\n  $label (${body.kind.name}): ${body.content}$suffix');
  }
}
