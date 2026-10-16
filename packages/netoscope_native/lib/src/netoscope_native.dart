import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:netoscope/netoscope.dart';

/// Forwards HTTP calls captured by native Android and iOS code to Netoscope.
///
/// - **Android:** add `NetoscopeInterceptor()` to the OkHttp clients your
///   native code (or SDKs that accept a client) uses.
/// - **iOS:** `URLSession.shared` and `NSURLConnection` traffic is captured
///   automatically. Pass `captureAllUrlSessions: true` to also capture
///   sessions created with `URLSessionConfiguration.default`/`.ephemeral`,
///   or call `NetoscopeURLProtocol.enable(on:)` for specific configurations.
///
/// Calls are redacted, truncated and inspected in Dart like any other call;
/// their metadata `source` is `android` or `ios`.
abstract final class NetoscopeNative {
  static const EventChannel _calls = EventChannel('dev.netoscope/native_calls');
  static const MethodChannel _control =
      MethodChannel('dev.netoscope/native_control');

  static StreamSubscription<Object?>? _subscription;

  /// Whether native calls are being forwarded.
  static bool get isAttached => _subscription != null;

  /// Starts forwarding native calls to [netoscope]. Returns `false` when
  /// logging is disabled for this build, on unsupported platforms, or when
  /// the plugin is not available.
  static Future<bool> attach(
    Netoscope netoscope, {
    bool captureAllUrlSessions = false,
  }) async {
    final platform = defaultTargetPlatform;
    if (kIsWeb ||
        !netoscope.isEnabled ||
        (platform != TargetPlatform.android &&
            platform != TargetPlatform.iOS)) {
      return false;
    }
    await detach();
    try {
      await _control.invokeMethod<bool>('configure', {
        'captureAllUrlSessions': captureAllUrlSessions,
      });
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
    _subscription = _calls.receiveBroadcastStream().listen(
      (event) {
        final call = parseNativeCall(event);
        if (call != null) netoscope.recordExternalCall(call);
      },
      onError: (Object _) {},
    );
    return true;
  }

  /// Stops forwarding native calls.
  static Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// Converts an event from the native side into an [ExternalNetworkCall].
/// Returns `null` for malformed events.
@visibleForTesting
ExternalNetworkCall? parseNativeCall(Object? event) {
  if (event is! Map) return null;
  final url = Uri.tryParse('${event['url'] ?? ''}');
  final method = event['method'];
  final startedAt = event['startedAt'];
  if (url == null || !url.hasScheme || method is! String || startedAt is! num) {
    return null;
  }
  Map<String, String> headers(Object? value) => value is Map
      ? {
          for (final e in value.entries)
            if (e.value != null) '${e.key}': '${e.value}',
        }
      : const {};
  Object? body(Object? value) => value is Uint8List && value.isNotEmpty
      ? value
      : (value is String ? value : null);
  final micros = event['durationMicros'];
  final status = event['statusCode'];
  final error = event['error'];
  return ExternalNetworkCall(
    method: method,
    url: url,
    startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt.toInt()),
    duration: micros is num ? Duration(microseconds: micros.toInt()) : null,
    requestHeaders: headers(event['requestHeaders']),
    requestBody: body(event['requestBody']),
    statusCode: status is num && status > 0 ? status.toInt() : null,
    responseHeaders: headers(event['responseHeaders']),
    responseBody: body(event['responseBody']),
    error: error is String ? error : null,
    errorType: switch (event['errorType']) {
      'timeout' => NetworkErrorType.timeout,
      'connection' => NetworkErrorType.connection,
      'badCertificate' => NetworkErrorType.badCertificate,
      'cancelled' => NetworkErrorType.cancelled,
      _ => NetworkErrorType.unknown,
    },
    source: event['source'] is String ? event['source'] as String : 'native',
  );
}
