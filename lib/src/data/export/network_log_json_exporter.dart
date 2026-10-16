import 'dart:convert';

import '../../core/entities/network_log_entry.dart';

/// Serializes entries to indented JSON for copying or sharing.
///
/// Entries are already redacted, so the export contains only what the
/// inspector shows.
String exportNetworkLogsAsJson(
  Iterable<NetworkLogEntry> entries, {
  DateTime? exportedAt,
}) {
  final list = [for (final entry in entries) entry.toJson()];
  return const JsonEncoder.withIndent('  ').convert({
    'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
    'count': list.length,
    'entries': list,
  });
}
