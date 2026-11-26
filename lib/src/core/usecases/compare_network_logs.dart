import 'dart:convert';
import 'dart:typed_data';

import '../entities/network_log_body.dart';
import '../entities/network_log_entry.dart';

/// How a value differs between two calls.
enum NetworkLogDiffChange {
  /// Present in both calls with the same value.
  unchanged,

  /// Present in both calls with different values.
  changed,

  /// Only present in the second (newer) call.
  added,

  /// Only present in the first (older) call.
  removed,
}

/// One named value (a header, a query parameter, the status code…) in both
/// calls.
class NetworkLogFieldDiff {
  /// Creates a field difference. `null` means the field is absent.
  const NetworkLogFieldDiff(this.name, this.before, this.after);

  /// The field name, such as `content-type` or `Status`.
  final String name;

  /// The value in the first call, or `null` when absent.
  final String? before;

  /// The value in the second call, or `null` when absent.
  final String? after;

  /// How the value changed.
  NetworkLogDiffChange get change {
    if (before == after) return NetworkLogDiffChange.unchanged;
    if (before == null) return NetworkLogDiffChange.added;
    if (after == null) return NetworkLogDiffChange.removed;
    return NetworkLogDiffChange.changed;
  }

  @override
  String toString() => 'NetworkLogFieldDiff($name: $before → $after)';
}

/// One line of a body difference.
class NetworkLogLineDiff {
  /// Creates a line. [change] is never [NetworkLogDiffChange.changed]: a changed line
  /// is a removed line followed by an added one.
  const NetworkLogLineDiff(this.change, this.text);

  /// Whether the line is in both bodies, only the first or only the second.
  final NetworkLogDiffChange change;

  /// The line, without its line break.
  final String text;

  @override
  String toString() => switch (change) {
        NetworkLogDiffChange.added => '+ $text',
        NetworkLogDiffChange.removed => '- $text',
        _ => '  $text',
      };
}

/// The differences between two recorded calls, typically two calls to the
/// same endpoint.
///
/// Built from already-redacted entries, so masked values compare equal and
/// secrets never show up as a difference. JSON bodies are compared
/// pretty-printed, line by line.
class NetworkLogComparison {
  /// Compares [before] (usually the older call) with [after].
  factory NetworkLogComparison(NetworkLogEntry before, NetworkLogEntry after) {
    return NetworkLogComparison._(
      before: before,
      after: after,
      summary: [
        NetworkLogFieldDiff('Method', before.method, after.method),
        NetworkLogFieldDiff('URL', '${before.url}', '${after.url}'),
        NetworkLogFieldDiff('Status', _status(before), _status(after)),
        NetworkLogFieldDiff(
            'Duration', _ms(before.duration), _ms(after.duration)),
        NetworkLogFieldDiff(
          'Sent',
          before.requestSize?.toString(),
          after.requestSize?.toString(),
        ),
        NetworkLogFieldDiff(
          'Received',
          before.responseSize?.toString(),
          after.responseSize?.toString(),
        ),
        if (before.error != null || after.error != null)
          NetworkLogFieldDiff(
              'Error', before.error?.message, after.error?.message),
      ],
      queryParameters: _fields(
        _joinedQuery(before.queryParameters),
        _joinedQuery(after.queryParameters),
      ),
      requestHeaders: _fields(
        _lowerKeys(before.requestHeaders),
        _lowerKeys(after.requestHeaders),
      ),
      responseHeaders: _fields(
        _lowerKeys(before.responseHeaders),
        _lowerKeys(after.responseHeaders),
      ),
      requestBody: diffLines(
        _bodyText(before.requestBody),
        _bodyText(after.requestBody),
      ),
      responseBody: diffLines(
        _bodyText(before.responseBody),
        _bodyText(after.responseBody),
      ),
    );
  }

  NetworkLogComparison._({
    required this.before,
    required this.after,
    required this.summary,
    required this.queryParameters,
    required this.requestHeaders,
    required this.responseHeaders,
    required this.requestBody,
    required this.responseBody,
  });

  /// The first call.
  final NetworkLogEntry before;

  /// The second call.
  final NetworkLogEntry after;

  /// Method, URL, status, duration, sizes and error.
  final List<NetworkLogFieldDiff> summary;

  /// Query parameters, sorted by name.
  final List<NetworkLogFieldDiff> queryParameters;

  /// Request headers (names lower-cased), sorted by name.
  final List<NetworkLogFieldDiff> requestHeaders;

  /// Response headers (names lower-cased), sorted by name.
  final List<NetworkLogFieldDiff> responseHeaders;

  /// The request bodies, line by line.
  final List<NetworkLogLineDiff> requestBody;

  /// The response bodies, line by line.
  final List<NetworkLogLineDiff> responseBody;

  /// Whether anything other than the timing differs.
  bool get hasDifferences =>
      [
        for (final field in summary)
          if (field.name != 'Duration') field,
        ...queryParameters,
        ...requestHeaders,
        ...responseHeaders,
      ].any((field) => field.change != NetworkLogDiffChange.unchanged) ||
      [...requestBody, ...responseBody]
          .any((line) => line.change != NetworkLogDiffChange.unchanged);

  /// The most lines compared exactly; longer bodies with many differences
  /// fall back to showing the differing middle as removed then added.
  static const int maxDiffLines = 1000;

  /// A line diff of [before] and [after] (the longest common subsequence of
  /// lines). `null` means no body and produces no lines.
  static List<NetworkLogLineDiff> diffLines(String? before, String? after) {
    final a = before == null
        ? const <String>[]
        : const LineSplitter().convert(before);
    final b =
        after == null ? const <String>[] : const LineSplitter().convert(after);
    var start = 0;
    while (start < a.length && start < b.length && a[start] == b[start]) {
      start++;
    }
    var endA = a.length;
    var endB = b.length;
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }
    final result = <NetworkLogLineDiff>[
      for (var i = 0; i < start; i++)
        NetworkLogLineDiff(NetworkLogDiffChange.unchanged, a[i]),
    ];
    final midA = a.sublist(start, endA);
    final midB = b.sublist(start, endB);
    if (midA.length > maxDiffLines || midB.length > maxDiffLines) {
      result
        ..addAll([
          for (final l in midA)
            NetworkLogLineDiff(NetworkLogDiffChange.removed, l)
        ])
        ..addAll([
          for (final l in midB)
            NetworkLogLineDiff(NetworkLogDiffChange.added, l)
        ]);
    } else {
      result.addAll(_lcs(midA, midB));
    }
    for (var i = endA; i < a.length; i++) {
      result.add(NetworkLogLineDiff(NetworkLogDiffChange.unchanged, a[i]));
    }
    return result;
  }

  static List<NetworkLogLineDiff> _lcs(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    // lengths[i * (m + 1) + j] is the LCS length of a[i..] and b[j..].
    final lengths = Uint16List((n + 1) * (m + 1));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        final index = i * (m + 1) + j;
        lengths[index] = a[i] == b[j]
            ? lengths[index + m + 2] + 1
            : _max(lengths[index + m + 1], lengths[index + 1]);
      }
    }
    final result = <NetworkLogLineDiff>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        result.add(NetworkLogLineDiff(NetworkLogDiffChange.unchanged, a[i]));
        i++;
        j++;
      } else if (lengths[(i + 1) * (m + 1) + j] >=
          lengths[i * (m + 1) + j + 1]) {
        result.add(NetworkLogLineDiff(NetworkLogDiffChange.removed, a[i++]));
      } else {
        result.add(NetworkLogLineDiff(NetworkLogDiffChange.added, b[j++]));
      }
    }
    while (i < n) {
      result.add(NetworkLogLineDiff(NetworkLogDiffChange.removed, a[i++]));
    }
    while (j < m) {
      result.add(NetworkLogLineDiff(NetworkLogDiffChange.added, b[j++]));
    }
    return result;
  }

  static int _max(int a, int b) => a > b ? a : b;

  static String? _status(NetworkLogEntry entry) =>
      entry.statusCode?.toString() ?? entry.outcome.name;

  static String? _ms(Duration? duration) =>
      duration == null ? null : '${duration.inMilliseconds} ms';

  static Map<String, String> _lowerKeys(Map<String, String> map) => {
        for (final entry in map.entries) entry.key.toLowerCase(): entry.value,
      };

  static Map<String, String> _joinedQuery(Map<String, List<String>> query) => {
        for (final entry in query.entries) entry.key: entry.value.join(', '),
      };

  static List<NetworkLogFieldDiff> _fields(
    Map<String, String> before,
    Map<String, String> after,
  ) {
    final names = {...before.keys, ...after.keys}.toList()..sort();
    return [
      for (final name in names)
        NetworkLogFieldDiff(name, before[name], after[name]),
    ];
  }

  /// The comparable text of [body]: pretty-printed when it is complete JSON.
  static String? _bodyText(NetworkLogBody? body) {
    if (body == null) return null;
    final content = body.content;
    if (body.isTruncated) return content;
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(content));
      } on FormatException {
        return content;
      }
    }
    return content;
  }
}
