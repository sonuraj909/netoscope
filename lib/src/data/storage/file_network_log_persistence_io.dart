import 'dart:convert';
import 'dart:io';

import '../../core/contracts/network_log_persistence.dart';
import '../../core/entities/network_log_entry.dart';

/// Saves history to a JSON file at [path].
///
/// Writes go to a temporary file that is then renamed over [path], so a
/// crash mid-write never leaves a corrupt history. Use a private app
/// directory, such as `getApplicationSupportDirectory()` from
/// `path_provider`.
class FileNetworkLogPersistence implements NetworkLogPersistence {
  /// Creates a persistence storing at [path].
  FileNetworkLogPersistence(this.path);

  /// The file path.
  final String path;

  static const int _version = 1;

  @override
  Future<List<NetworkLogEntry>> load() async {
    try {
      final file = File(path);
      if (!file.existsSync()) return const [];
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['version'] != _version) return const [];
      final entries = json['entries'];
      if (entries is! List) return const [];
      return [
        for (final item in entries)
          if (item is Map)
            NetworkLogEntry.fromJson(item.map((k, v) => MapEntry('$k', v))),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<NetworkLogEntry> entries) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(
      jsonEncode({
        'version': _version,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'entries': [for (final entry in entries) entry.toJson()],
      }),
      flush: true,
    );
    await temp.rename(path);
  }
}
