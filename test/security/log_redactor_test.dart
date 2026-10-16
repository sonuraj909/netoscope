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
}
