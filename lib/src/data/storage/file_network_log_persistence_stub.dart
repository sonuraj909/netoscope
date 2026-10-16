import '../../core/contracts/network_log_persistence.dart';
import '../../core/entities/network_log_entry.dart';

/// Saves history to a JSON file. Not available on the web.
class FileNetworkLogPersistence implements NetworkLogPersistence {
  /// Throws [UnsupportedError]: there is no file system on the web.
  FileNetworkLogPersistence(String path) {
    throw UnsupportedError('File persistence is not available on the web.');
  }

  @override
  Future<List<NetworkLogEntry>> load() async => const [];

  @override
  Future<void> save(List<NetworkLogEntry> entries) async {}
}
