import 'package:flutter/material.dart';

import '../../core/entities/network_log_entry.dart';

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
  /// Creates a badge.
  const LogBadge({super.key, required this.label, required this.color});

  /// The text shown.
  final String label;

  /// The accent color.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
