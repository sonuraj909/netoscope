import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/data/export/curl_exporter.dart';

import '../support/fixtures.dart';

void main() {
  test('builds a GET without -X', () {
    final curl = buildCurlCommand(
      makeEntry(
        url: 'https://api.dev/users?page=2',
        requestHeaders: {'accept': 'application/json', 'content-length': '0'},
      ),
    )!;
    expect(
      curl.command,
      "curl \\\n  'https://api.dev/users?page=2' \\\n  -H 'accept: application/json'",
    );
    expect(curl.containsRedactedValues, isFalse);
    expect(curl.bodyOmitted, isFalse);
  });

  test('adds the body and flags redacted values', () {
    final curl = buildCurlCommand(
      makeEntry(
        method: 'POST',
        url: 'https://api.dev/login',
        requestHeaders: {'Authorization': '***'},
        requestBody: const NetworkLogBody(
          kind: NetworkBodyKind.json,
          content: '{"user":"o\'neil","password":"***"}',
        ),
      ),
    )!;
    expect(curl.command, contains("-H 'Authorization: ***'"));
    expect(
      curl.command,
      contains(r"""--data-raw '{"user":"o'\''neil","password":"***"}'"""),
    );
    expect(curl.command, isNot(contains('-X POST')));
    expect(curl.containsRedactedValues, isTrue);
  });

  test('keeps explicit methods and omits binary or truncated bodies', () {
    final put = buildCurlCommand(
      makeEntry(
        method: 'PUT',
        requestBody: const NetworkLogBody(
          kind: NetworkBodyKind.binary,
          content: '<binary, 3 bytes>',
        ),
      ),
    )!;
    expect(put.command, contains('-X PUT'));
    expect(put.command, isNot(contains('--data')));
    expect(put.bodyOmitted, isTrue);
  });

  test('turns multipart descriptions into -F options', () {
    final curl = buildCurlCommand(
      makeEntry(
        method: 'POST',
        requestHeaders: {'content-type': 'multipart/form-data; boundary=x'},
        requestBody: const NetworkLogBody(
          kind: NetworkBodyKind.multipart,
          content: '{"fields":[{"name":"title","value":"hi"}],'
              '"files":[{"field":"doc","filename":"a.txt",'
              '"contentType":"text/plain","length":3}]}',
        ),
      ),
    )!;
    expect(curl.command, contains("-F 'title=hi'"));
    expect(curl.command, contains("-F 'doc=@a.txt;type=text/plain'"));
    expect(curl.command, isNot(contains('content-type')));
  });

  test('is not available for messages or non-HTTP URLs', () {
    expect(
      buildCurlCommand(
        NetworkLogEntry(
          id: 'm',
          method: 'WS',
          url: Uri.parse('wss://rt.dev'),
          timestamp: DateTime(2026),
          kind: NetworkEventKind.message,
        ),
      ),
      isNull,
    );
    expect(
      buildCurlCommand(makeEntry(url: 'grpc://unknown/a.B/C')),
      isNull,
    );
  });
}
