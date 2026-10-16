import 'package:flutter/material.dart';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/protocol_details.dart';

bool _isDark(ColorScheme scheme) => scheme.brightness == Brightness.dark;

/// The accent color for successful calls, readable in light and dark themes.
Color successColor(ColorScheme scheme) =>
    _isDark(scheme) ? Colors.green.shade300 : Colors.green.shade700;

/// The accent color for warnings (4xx, slow calls) in light and dark themes.
Color warningColor(ColorScheme scheme) =>
    _isDark(scheme) ? Colors.orange.shade300 : Colors.orange.shade800;

/// The accent color for an entry's outcome.
Color outcomeColor(NetworkLogEntry entry, ColorScheme scheme) {
  return switch (entry.outcome) {
    NetworkLogOutcome.success => successColor(scheme),
    NetworkLogOutcome.httpError =>
      (entry.statusCode ?? 0) >= 500 ? scheme.error : warningColor(scheme),
    NetworkLogOutcome.failure => scheme.error,
    NetworkLogOutcome.cancelled => scheme.outline,
  };
}

/// A short status label: the code, or the outcome when there is none.
String statusLabel(NetworkLogEntry entry) =>
    entry.statusCode?.toString() ??
    switch (entry.outcome) {
      NetworkLogOutcome.cancelled => 'CANCELLED',
      _ => entry.error?.type.name.toUpperCase() ?? 'FAILED',
    };

/// Formats [duration] as milliseconds or seconds.
String formatDuration(Duration? duration) {
  if (duration == null) return '–';
  final ms = duration.inMilliseconds;
  return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(2)} s';
}

/// Formats a byte count.
String formatBytes(int? bytes) {
  if (bytes == null) return '–';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Formats [time] in local time as `HH:mm:ss.SSS`.
String formatTime(DateTime time) {
  final local = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
      '.${local.millisecond.toString().padLeft(3, '0')}';
}

/// A compact colored label, used for methods and status codes.
class LogBadge extends StatelessWidget {
  /// Creates a badge. [filled] uses a tinted background instead of an
  /// outline.
  const LogBadge({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
  });

  /// The text shown.
  final String label;

  /// The accent color.
  final Color color;

  /// Whether the badge has a tinted background.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? color.withAlpha(40) : null,
        border: filled ? null : Border.all(color: color),
        borderRadius: BorderRadius.circular(filled ? 20 : 4),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: filled ? 8 : 6, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
        ),
      ),
    );
  }
}

/// The leading badge text: the HTTP method, or a protocol label with a
/// direction arrow or lifecycle stage.
String entryBadge(NetworkLogEntry entry) {
  switch (entry.kind) {
    case NetworkEventKind.exchange:
      return entry.protocol == NetworkProtocol.grpc
          ? (entry.detail<GrpcDetails>()?.label ?? 'gRPC')
          : entry.method;
    case NetworkEventKind.message:
      final arrow = entry.direction == MessageDirection.outgoing ? '↑' : '↓';
      return '${entry.method} $arrow';
    case NetworkEventKind.connection:
      final stage = switch (entry.lifecycle) {
        ConnectionLifecycle.opened => 'open',
        ConnectionLifecycle.closed => 'close',
        ConnectionLifecycle.failed => 'fail',
        null => '',
      };
      return '${entry.method} $stage'.trim();
  }
}

/// The row title: the path, or the most meaningful protocol label.
String entryTitle(NetworkLogEntry entry) {
  final path = entry.url.path.isEmpty ? '/' : entry.url.path;
  final graphQL = entry.graphQL;
  if (graphQL != null && graphQL.operations.isNotEmpty) {
    return '$path · ${graphQL.summary}';
  }
  final sse = entry.detail<SseDetails>();
  if (sse != null) return 'event: ${sse.eventType}';
  final topic = entry.detail<MqttDetails>()?.topic;
  if (topic != null) {
    final packet = entry.metadata['packet'];
    return packet == null ? topic : '$packet $topic';
  }
  return path;
}

/// The trailing status text.
String entryStatus(NetworkLogEntry entry) {
  switch (entry.kind) {
    case NetworkEventKind.exchange:
      final grpcStatus = entry.detail<GrpcDetails>()?.statusName;
      return grpcStatus ?? statusLabel(entry);
    case NetworkEventKind.message:
      return entry.messageBody?.format.label.toUpperCase() ?? 'MESSAGE';
    case NetworkEventKind.connection:
      return entry.lifecycle?.name.toUpperCase() ?? 'EVENT';
  }
}
