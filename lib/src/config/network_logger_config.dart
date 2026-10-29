import '../core/contracts/payload_decoder.dart';
import '../core/usecases/analyze_traffic.dart';
import '../protocols/webhook/webhook_config.dart';

/// How much of each call is written to the console.
enum ConsoleLogLevel {
  /// Nothing is written.
  none,

  /// One line per call: method, URL, status and duration, plus errors.
  summary,

  /// The summary plus (redacted) headers and bodies.
  verbose,
}

/// Which theme the in-app inspector uses.
enum InspectorThemeMode {
  /// Follows the host app's theme brightness.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
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
    this.consoleColors = false,
    this.showInspector = true,
    this.showFloatingButton = true,
    this.showNotification = true,
    this.inspectorThemeMode = InspectorThemeMode.system,
    this.maxHistorySize = 100,
    this.maxBodySize = 32 * 1024,
    this.captureRequestBody = true,
    this.captureResponseBody = true,
    this.captureHeaders = true,
    this.excludedUrls = const [],
    this.slowRequestThreshold = const Duration(seconds: 3),
    this.sensitiveKeys = const {},
    this.sensitiveHeaders = const {},
    this.sensitiveQueryParameters = const {},
    this.sensitiveBodyKeys = const {},
    this.redactionMask = '***',
    this.payloadDecoders = const [],
    this.detectGraphQL = true,
    this.webhooks = const WebhookConfig(),
    this.captureTransferProgress = true,
    this.captureRealtimeMessages = true,
    this.trafficAnalyzer = const TrafficAnalyzer(),
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

  /// Whether console output uses ANSI colors. Leave off for consoles that
  /// show escape codes literally.
  final bool consoleColors;

  /// Whether the floating inspector button starts visible. Can be changed
  /// at runtime with `Netoscope.setFloatingButtonEnabled`.
  final bool showFloatingButton;

  /// Whether the activity notification starts on (when a notifier is
  /// attached). Can be changed at runtime with
  /// `Netoscope.setNotificationEnabled`.
  final bool showNotification;

  /// Whether the in-app inspector and its button are available.
  final bool showInspector;

  /// The inspector's initial theme. [InspectorThemeMode.system] (the default)
  /// follows the host app's theme brightness; `light` and `dark` force one,
  /// for example a dark inspector in an app that only has a light theme.
  /// It can be switched at runtime from the inspector's settings or with
  /// `Netoscope.setInspectorThemeMode`.
  final InspectorThemeMode inspectorThemeMode;

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

  /// Extra header names whose values are redacted. Unlike [sensitiveKeys]
  /// they do not affect query parameters or bodies.
  final Set<String> sensitiveHeaders;

  /// Extra query parameter names whose values are redacted in URLs. `key`
  /// is always redacted in URLs. Unlike [sensitiveKeys] they do not affect
  /// headers or bodies (form-encoded bodies and free text excepted).
  final Set<String> sensitiveQueryParameters;

  /// Extra keys redacted in bodies: JSON at any depth, form and multipart
  /// fields, XML/HTML, GraphQL variables and arguments, and message
  /// payloads. Unlike [sensitiveKeys] they do not affect headers or URLs.
  final Set<String> sensitiveBodyKeys;

  /// The text that replaces redacted values.
  final String redactionMask;

  /// Custom payload decoders (for example a [PayloadDecoder] for Protocol
  /// Buffers or MessagePack), tried in order before built-in handling.
  final List<PayloadDecoder> payloadDecoders;

  /// Whether GraphQL operations and errors are recognized in HTTP calls.
  final bool detectGraphQL;

  /// How outbound webhook deliveries are recognized.
  final WebhookConfig webhooks;

  /// Whether Dio upload/download progress is recorded for requests that
  /// already have `onSendProgress`/`onReceiveProgress` callbacks.
  final bool captureTransferProgress;

  /// Whether individual WebSocket, SSE, gRPC-stream and MQTT messages are
  /// recorded. Connection lifecycle events are always recorded. Chatty
  /// connections evict older history, so consider turning this off or
  /// filtering messages per connection.
  final bool captureRealtimeMessages;

  /// How duplicate and N+1 requests are detected.
  final TrafficAnalyzer trafficAnalyzer;

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
