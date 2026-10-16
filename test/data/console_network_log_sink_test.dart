import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import '../support/fixtures.dart';

void main() {
  final entry = makeEntry(
    method: 'POST',
    url: 'https://api.example.com/login',
    duration: const Duration(seconds: 4),
    requestHeaders: {'authorization': '***'},
    requestBody: const NetworkLogBody(
      kind: NetworkBodyKind.json,
      content: '{"password":"***"}',
    ),
  );

  test('writes nothing when the level is none', () {
    final lines = <String>[];
    ConsoleNetworkLogSink(level: ConsoleLogLevel.none, output: lines.add)
        .write(entry);
    expect(lines, isEmpty);
  });

  test('summary is a single line with status, duration and slow flag', () {
    final lines = <String>[];
    ConsoleNetworkLogSink(output: lines.add).write(entry);

    expect(lines, [
      'POST https://api.example.com/login → 200 (4000 ms) [SLOW]',
    ]);
  });

  test('summary includes the error for failures', () {
    final lines = <String>[];
    ConsoleNetworkLogSink(output: lines.add).write(
      makeEntry(
        statusCode: null,
        duration: null,
        error: const NetworkLogError(
          type: NetworkErrorType.connection,
          message: 'Connection refused',
        ),
      ),
    );
    expect(
      lines.single,
      'GET https://api.example.com/users → FAILURE\n'
      '  error: connection: Connection refused',
    );
  });

  test('verbose adds the already-redacted headers and bodies', () {
    final lines = <String>[];
    ConsoleNetworkLogSink(level: ConsoleLogLevel.verbose, output: lines.add)
        .write(entry);

    expect(lines.single, contains('authorization: ***'));
    expect(lines.single, contains('request body (json): {"password":"***"}'));
  });
}
