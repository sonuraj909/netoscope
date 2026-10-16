import 'package:netoscope/netoscope.dart';

/// Builds an entry with sensible defaults for tests.
NetworkLogEntry makeEntry({
  String id = '1',
  String method = 'GET',
  String url = 'https://api.example.com/users',
  int? statusCode = 200,
  Duration? duration = const Duration(milliseconds: 120),
  NetworkLogError? error,
  Map<String, String> requestHeaders = const {},
  Map<String, String> responseHeaders = const {},
  NetworkLogBody? requestBody,
  NetworkLogBody? responseBody,
  DateTime? timestamp,
}) =>
    NetworkLogEntry(
      id: id,
      method: method,
      url: Uri.parse(url),
      timestamp: timestamp ?? DateTime.utc(2026, 1, 1, 12),
      statusCode: statusCode,
      duration: duration,
      error: error,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      requestBody: requestBody,
      responseBody: responseBody,
    );

/// A sink that keeps everything it receives.
class RecordingSink implements NetworkLogSink {
  final List<NetworkLogEntry> received = [];

  @override
  void write(NetworkLogEntry entry) => received.add(entry);
}
