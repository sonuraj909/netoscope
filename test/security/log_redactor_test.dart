import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/src/security/log_redactor.dart';

void main() {
  final redactor = LogRedactor();

  group('sensitive keys', () {
    test('recognizes common credentials regardless of style', () {
      for (final key in [
        'Authorization',
        'proxy-authorization',
        'Cookie',
        'Set-Cookie',
        'X-API-Key',
        'api_key',
        'apiKey',
        'access_token',
        'refreshToken',
        'id-token',
        'password',
        'newPassword',
        'client_secret',
        'otp',
        'OTP',
        'pin',
        'session_id',
      ]) {
        expect(redactor.isSensitiveKey(key), isTrue, reason: key);
      }
    });

    test('does not flag ordinary keys', () {
      for (final key in ['id', 'name', 'email', 'footprint', 'code', 'page']) {
        expect(redactor.isSensitiveKey(key), isFalse, reason: key);
      }
    });

    test('supports extra keys with normalized matching', () {
      final custom = LogRedactor(extraKeys: ['national-id']);
      expect(custom.isSensitiveKey('National_ID'), isTrue);
      expect(custom.isSensitiveKey('nationality'), isFalse);
    });
  });

  test('redacts headers and keeps the rest', () {
    expect(
      redactor.redactHeaders({
        'Authorization': 'Bearer abc',
        'set-cookie': 'sid=1',
        'Accept': 'application/json',
      }),
      {
        'Authorization': '***',
        'set-cookie': '***',
        'Accept': 'application/json',
      },
    );
  });

  group('redactUrl', () {
    test('masks sensitive query values and keeps the others', () {
      final url = redactor.redactUrl(
        Uri.parse('https://api.dev/x?api_key=k1&page=2&token=a&token=b'),
      );
      expect(url.queryParametersAll, {
        'api_key': ['***'],
        'page': ['2'],
        'token': ['***', '***'],
      });
      expect(url.toString(), isNot(contains('k1')));
    });

    test('masks user info', () {
      final url = redactor.redactUrl(Uri.parse('https://user:pw@api.dev/x'));
      expect(url.userInfo, '***');
    });

    test('leaves URLs without secrets untouched', () {
      final original = Uri.parse('https://api.dev/x?page=1');
      expect(redactor.redactUrl(original), same(original));
    });
  });

  group('redactValue', () {
    test('masks nested map and list values without mutating input', () {
      final input = {
        'user': {
          'name': 'Ada',
          'password': 'hunter2',
          'devices': [
            {'id': 1, 'refresh_token': 'r1'},
          ],
        },
        'otp': 123456,
      };
      final output = redactor.redactValue(input);

      expect(output, {
        'user': {
          'name': 'Ada',
          'password': '***',
          'devices': [
            {'id': 1, 'refresh_token': '***'},
          ],
        },
        'otp': '***',
      });
      expect((input['user']! as Map)['password'], 'hunter2');
    });

    test('replaces unknown objects with a type placeholder', () {
      expect(redactor.redactValue([DateTime(2026)]), ['<DateTime>']);
    });

    test('limits nesting depth', () {
      Object nested = 'leaf';
      for (var i = 0; i < 40; i++) {
        nested = [nested];
      }
      expect(redactor.redactValue(nested).toString(), contains('<max depth>'));
    });

    test('uses the configured mask', () {
      expect(LogRedactor(mask: '[hidden]').redactValue({'token': 'x'}), {
        'token': '[hidden]',
      });
    });
  });

  group('redactText', () {
    test('masks JSON pairs, including in truncated JSON', () {
      expect(
        redactor.redactText('{"user":"ada","password":"hun'),
        '{"user":"ada","password":"***"',
      );
      expect(
        redactor.redactText('{"otp": 123456, "ok": true}'),
        '{"otp": "***", "ok": true}',
      );
    });

    test('masks form-encoded pairs', () {
      expect(
        redactor.redactText('username=ada&password=s3cret&remember=1'),
        'username=ada&password=***&remember=1',
      );
    });

    test('masks bearer and basic credentials in free text', () {
      expect(
        redactor.redactText('failed with Bearer eyJhbGciOi.payload.sig'),
        'failed with Bearer ***',
      );
    });
  });
  group('scoped keys', () {
    final scoped = LogRedactor(
      headerKeys: ['X-Customer-Ref'],
      queryKeys: ['ref'],
      bodyKeys: ['national_id'],
    );

    test('apply only to their own scope', () {
      expect(scoped.isSensitiveHeader('x-customer-ref'), isTrue);
      expect(scoped.isSensitiveBodyKey('x-customer-ref'), isFalse);
      expect(scoped.isSensitiveQueryParameter('ref'), isTrue);
      expect(scoped.isSensitiveHeader('ref'), isFalse);
      expect(scoped.isSensitiveBodyKey('National-ID'), isTrue);
      expect(scoped.isSensitiveQueryParameter('national_id'), isFalse);
    });

    test('are used by the matching redaction', () {
      expect(
        scoped.redactHeaders({'X-Customer-Ref': 'c1', 'ref': 'r1'}),
        {'X-Customer-Ref': '***', 'ref': 'r1'},
      );
      expect(
        scoped.redactUrl(Uri.parse('https://a.dev/?ref=r1&national_id=n1')),
        Uri.parse('https://a.dev/?ref=%2A%2A%2A&national_id=n1'),
      );
      expect(
        scoped.redactValue({'national_id': 'n1', 'ref': 'r1'}),
        {'national_id': '***', 'ref': 'r1'},
      );
    });

    test('all apply to free text of unknown origin', () {
      expect(
        scoped.redactText('ref=r1&national_id=n1&x-customer-ref=c1&a=1'),
        'ref=***&national_id=***&x-customer-ref=***&a=1',
      );
    });

    test('key is sensitive in URLs only', () {
      expect(redactor.isSensitiveQueryParameter('key'), isTrue);
      expect(redactor.isSensitiveBodyKey('key'), isFalse);
      expect(
        redactor.redactUrl(Uri.parse('https://maps.dev/x?key=AIza1&q=a')),
        Uri.parse('https://maps.dev/x?key=%2A%2A%2A&q=a'),
      );
    });
  });

  group('values under ordinary keys', () {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln';

    test('embedded JSON documents are redacted by key', () {
      expect(
        redactor.redactValue({
          'payload': '{"password":"pw","nested":[{"api_key":"k"}],"n":1}',
          'plain': '{not json',
        }),
        {
          'payload': '{"password":"***","nested":[{"api_key":"***"}],"n":1}',
          'plain': '{not json',
        },
      );
    });

    test('unchanged embedded JSON keeps its original text', () {
      const text = '{ "a": 1,  "b": [true] }';
      expect(redactor.redactString(text), same(text));
    });

    test('credentials, JWTs and URL secrets are masked', () {
      expect(
        redactor.redactValue({
          'note': 'use Bearer abc.def',
          'trace': jwt,
          'next': 'https://a.dev/cb?token=t1&page=2',
          'repo': 'https://ghp_abc@github.com/o/r.git',
        }),
        {
          'note': 'use Bearer ***',
          'trace': '***',
          'next': 'https://a.dev/cb?token=***&page=2',
          'repo': 'https://***@github.com/o/r.git',
        },
      );
    });

    test('header values are scanned too', () {
      expect(
        redactor.redactHeaders({
          'X-Upstream': 'Bearer abc',
          'X-Trace': jwt,
          'Location': 'https://a.dev/cb#access_token=t1&state=s',
          'Content-Type': 'application/json; charset=utf-8',
        }),
        {
          'X-Upstream': 'Bearer ***',
          'X-Trace': '***',
          'Location': 'https://a.dev/cb#access_token=***&state=s',
          'Content-Type': 'application/json; charset=utf-8',
        },
      );
    });
  });

  group('redactUrl beyond query keys', () {
    test('masks secrets in the fragment', () {
      final url = redactor.redactUrl(
        Uri.parse('https://app.dev/cb#access_token=t1&token_type=bearer&x=1'),
      );
      expect(url.fragment, 'access_token=***&token_type=***&x=1');
    });

    test('redacts JSON query values such as GraphQL variables', () {
      final url = redactor.redactUrl(
        Uri.https('api.dev', '/graphql', {
          'query': 'query Q { me }',
          'variables': '{"password":"pw","id":1}',
        }),
      );
      expect(url.queryParameters['variables'], '{"password":"***","id":1}');
      expect(url.queryParameters['query'], 'query Q { me }');
    });

    test('masks JWTs in the path', () {
      final url = redactor.redactUrl(Uri.parse(
        'https://api.dev/verify/eyJhbGciOiJub25lIn0.eyJzdWIiOiIxIn0.sig/ok',
      ));
      expect(url.path, '/verify/***/ok');
    });
  });

  group('redactText edge cases', () {
    test('masks whole objects and arrays, even when cut off', () {
      expect(
        redactor.redactText(
          '{"session": {"id": "s1", "data": [1, "}"]}, "name": "Ada"}',
        ),
        '{"session": "***", "name": "Ada"}',
      );
      expect(
        redactor.redactText('{"name": "Ada", "credentials": [{"user": "u", '),
        '{"name": "Ada", "credentials": "***"',
      );
    });

    test('decodes percent-encoded form keys', () {
      expect(
        redactor.redactText('user%5Bpassword%5D=pw&user%5Bname%5D=ada'),
        'user%5Bpassword%5D=***&user%5Bname%5D=ada',
      );
    });

    test('finds query secrets inside other values', () {
      expect(
        redactor.redactText('ClientException: x, uri=https://a.dev/?token=t1'),
        'ClientException: x, uri=https://a.dev/?token=***',
      );
    });

    test('masks URL user info', () {
      expect(
        redactor.redactText('failed: https://bob:pw@a.dev/x'),
        'failed: https://***@a.dev/x',
      );
    });

    test('masks key: value pairs in plain text', () {
      expect(
        redactor.redactText(
          'password: hunter2\nuser: ada\nAuthorization: Bearer abc\n'
          "token: 'q t'\ntime: 12:30",
        ),
        'password: ***\nuser: ada\nAuthorization: ***\n'
        'token: ***\ntime: 12:30',
      );
    });

    test('leaves text without secrets untouched', () {
      const text = 'GET https://a.dev/x?page=1 failed: timeout after 3s';
      expect(redactor.redactText(text), same(text));
    });
  });
}
