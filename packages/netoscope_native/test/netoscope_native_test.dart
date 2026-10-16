import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope_native/netoscope_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const control = MethodChannel('dev.netoscope/native_control');
  const calls = 'dev.netoscope/native_calls';

  Map<String, Object?> event({Map<String, Object?> extra = const {}}) => {
        'source': 'android',
        'method': 'POST',
        'url': 'https://api.dev/login?token=abc',
        'startedAt': DateTime.utc(2026).millisecondsSinceEpoch,
        'durationMicros': 123456,
        'requestHeaders': {
          'Authorization': 'Bearer t',
          'Content-Type': 'application/json'
        },
        'requestBody': Uint8List.fromList(utf8.encode('{"password":"p"}')),
        'statusCode': 200,
        'responseHeaders': {'Content-Type': 'application/json'},
        'responseBody': Uint8List.fromList(utf8.encode('{"ok":true}')),
        ...extra,
      };

  group('parseNativeCall', () {
    test('maps a native event', () {
      final call = parseNativeCall(event())!;
      expect(call.method, 'POST');
      expect(call.url.path, '/login');
      expect(call.duration, const Duration(microseconds: 123456));
      expect(call.statusCode, 200);
      expect(call.source, 'android');
      expect(call.requestBody, isA<Uint8List>());
    });

    test('maps failures', () {
      final call = parseNativeCall(event(extra: {
        'statusCode': null,
        'error': 'timeout',
        'errorType': 'timeout',
      }))!;
      expect(call.statusCode, isNull);
      expect(call.errorType, NetworkErrorType.timeout);
    });

    test('rejects malformed events', () {
      expect(parseNativeCall('nope'), isNull);
      expect(parseNativeCall({'method': 'GET'}), isNull);
      expect(parseNativeCall(event(extra: {'url': 'not a url'})), isNull);
    });
  });

  group('attach', () {
    late Netoscope netoscope;
    setUp(() => netoscope = Netoscope(
          config:
              const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
        ));
    tearDown(() async {
      await NetoscopeNative.detach();
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockMethodCallHandler(control, null)
        ..setMockStreamHandler(const EventChannel(calls), null);
    });

    test('records native calls with redaction', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      Map<Object?, Object?>? configured;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(control, (call) async {
        configured = call.arguments as Map<Object?, Object?>?;
        return true;
      });
      messenger.setMockStreamHandler(
        const EventChannel(calls),
        MockStreamHandler.inline(
          onListen: (arguments, sink) => sink.success(event()),
        ),
      );

      expect(
        await NetoscopeNative.attach(netoscope, captureAllUrlSessions: true),
        isTrue,
      );
      await pumpEventQueue();

      expect(configured, {'captureAllUrlSessions': true});
      expect(NetoscopeNative.isAttached, isTrue);
      final entry = netoscope.logs.single;
      expect(entry.metadata['source'], 'android');
      expect(entry.queryParameters['token'], ['***']);
      expect(entry.requestHeaders['Authorization'], '***');
      expect(entry.requestBody!.content, '{"password":"***"}');
      expect(entry.responseBody!.content, '{"ok":true}');
    });

    test('is a no-op without the plugin or on other platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await NetoscopeNative.attach(netoscope), isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(await NetoscopeNative.attach(netoscope), isFalse);

      final disabled =
          Netoscope(config: const NetworkLoggerConfig(enabled: false));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await NetoscopeNative.attach(disabled), isFalse);
    });
  });
}
