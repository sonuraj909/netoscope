import 'dart:developer' as developer;

import '../../config/network_logger_config.dart';
import '../../core/contracts/network_log_sink.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';

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
    }
    return buffer.toString();
  }

  String _summary(NetworkLogEntry entry) {
    final status =
        entry.statusCode?.toString() ?? entry.outcome.name.toUpperCase();
    final duration = entry.duration;
    final time = duration == null ? '' : ' (${duration.inMilliseconds} ms)';
    final slow = entry.isSlower(slowRequestThreshold) ? ' [SLOW]' : '';
    return '${entry.method} ${entry.url} → $status$time$slow';
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
