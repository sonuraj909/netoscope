/// How much of each call is written to the console.
enum ConsoleLogLevel {
  /// Nothing is written.
  none,

  /// One line per call: method, URL, status and duration, plus errors.
  summary,

  /// The summary plus (redacted) headers and bodies.
  verbose,
}

const bool _isReleaseMode = bool.fromEnvironment('dart.vm.product');

/// Resolves whether logging is active.
///
/// An explicit [enabled] value always wins; otherwise logging is active only
/// outside release builds.
bool resolveLoggingEnabled(bool? enabled, {required bool isReleaseMode}) =>
    enabled ?? !isReleaseMode;

/// Configuration for Netoscope.
///
/// The defaults are tuned for safe local debugging: logging is off in release
/// builds, sensitive keys are redacted and bodies are truncated.
class NetworkLoggerConfig {
  /// Creates a configuration.
  const NetworkLoggerConfig({
    this.enabled,
    this.consoleLogLevel = ConsoleLogLevel.summary,
    this.showInspector = true,
    this.maxHistorySize = 100,
    this.maxBodySize = 32 * 1024,
    this.captureRequestBody = true,
    this.captureResponseBody = true,
    this.captureHeaders = true,
    this.excludedUrls = const [],
    this.slowRequestThreshold = const Duration(seconds: 3),
    this.sensitiveKeys = const {},
    this.redactionMask = '***',
  })  : assert(maxHistorySize > 0, 'maxHistorySize must be positive'),
        assert(maxBodySize >= 0, 'maxBodySize must not be negative');

  /// Whether calls are logged at all.
  ///
  /// `null` (the default) enables logging in debug and profile builds and
  /// disables it in release builds. Set `true` to log in release builds
  /// deliberately; captured data can still contain personal information.
  final bool? enabled;

  /// How much is written to the console for each call.
  final ConsoleLogLevel consoleLogLevel;

  /// Whether the in-app inspector and its button are available.
  final bool showInspector;

  /// The maximum number of calls kept in history. Older calls are evicted.
  final int maxHistorySize;

  /// The maximum number of characters kept per captured body. Longer bodies
  /// are truncated. `0` keeps only the body kind and size.
  final int maxBodySize;

  /// Whether request bodies are captured.
  final bool captureRequestBody;

  /// Whether response bodies are captured.
  final bool captureResponseBody;

  /// Whether request and response headers are captured.
  final bool captureHeaders;

  /// Calls whose URL matches any of these patterns are not logged.
  ///
  /// A [String] matches when the URL contains it; a [RegExp] matches when it
  /// finds a match anywhere in the URL.
  final List<Pattern> excludedUrls;

  /// Calls taking at least this long are flagged as slow.
  final Duration slowRequestThreshold;

  /// Extra header, query-parameter and body keys whose values are redacted,
  /// in addition to the built-in list. Matching ignores case, `-` and `_`.
  final Set<String> sensitiveKeys;

  /// The text that replaces redacted values.
  final String redactionMask;

  /// Whether logging is active for the current build mode.
  bool get isEnabled =>
      resolveLoggingEnabled(enabled, isReleaseMode: _isReleaseMode);

  /// Whether calls to [url] should be skipped.
  bool isExcluded(Uri url) {
    if (excludedUrls.isEmpty) return false;
    final text = url.toString();
    return excludedUrls.any((pattern) => text.contains(pattern));
  }
}
