// Runs inside the real app on a device or simulator:
//   flutter test integration_test -d <device>
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope_example/local_server.dart';
import 'package:netoscope_example/main.dart';
import 'package:netoscope_native/netoscope_native.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('netoscope_example/native');

  testWidgets('native and dart:io calls are captured and redacted', (
    tester,
  ) async {
    // Boot the app so its native demo channel is registered.
    await tester.pumpWidget(const NetoscopeExampleApp());
    final server = (await startLocalServer())!;
    final netoscope = Netoscope(
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    expect(
      await NetoscopeNative.attach(netoscope, captureAllUrlSessions: true),
      isTrue,
    );
    expect(netoscope.captureDartIo(), isTrue);

    Future<void> settle(int count) async {
      for (var i = 0; i < 100 && netoscope.logs.length < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
    }

    await tester.runAsync(
      () => channel.invokeMethod<String>('request', {
        'url': server.replace(path: '/native/profile').toString(),
      }),
    );
    await tester.runAsync(
      () => channel.invokeMethod<String>('request', {
        'url': server.replace(path: '/native/login').toString(),
        'body': '{"username":"grace","password":"cobol"}',
      }),
    );
    if (ios) {
      await tester.runAsync(
        () => channel.invokeMethod<String>('request', {
          'url': server.replace(path: '/native/profile').toString(),
          'session': 'custom',
        }),
      );
    }
    await tester.runAsync(() async {
      final client = http.Client();
      await client.get(server.replace(path: '/native/profile'));
      client.close();
    });
    final expected = ios ? 4 : 3;
    await settle(expected);

    final native = netoscope.logs
        .where((e) => e.metadata['source'] == (ios ? 'ios' : 'android'))
        .toList();
    expect(native, hasLength(ios ? 3 : 2));
    final login = native.firstWhere((e) => e.url.path == '/native/login');
    expect(login.method, 'POST');
    expect(login.statusCode, 200);
    expect(
      login.requestHeaders.entries
          .firstWhere((h) => h.key.toLowerCase() == 'authorization')
          .value,
      '***',
    );
    expect(login.requestBody!.content, '{"username":"grace","password":"***"}');
    final profile = native.firstWhere((e) => e.url.path == '/native/profile');
    expect(profile.responseBody!.content, contains('"session_token":"***"'));
    expect(profile.duration, isNotNull);

    final dartIo = netoscope.logs.where((e) => e.metadata['source'] == null);
    expect(dartIo, hasLength(1), reason: 'the dart:io call, recorded once');

    netoscope.stopCapturingDartIo();
    await NetoscopeNative.detach();
  });
}
