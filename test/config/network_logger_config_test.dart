import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/src/config/network_logger_config.dart';

void main() {
  test('has safe defaults', () {
    const config = NetworkLoggerConfig();
    expect(config.enabled, isNull);
    expect(config.consoleLogLevel, ConsoleLogLevel.summary);
    expect(config.maxHistorySize, 100);
    expect(config.maxBodySize, 32 * 1024);
    expect(config.redactionMask, '***');
    expect(config.excludedUrls, isEmpty);
  });

  group('release-mode default', () {
    test('logging is off in release builds unless explicitly enabled', () {
      expect(resolveLoggingEnabled(null, isReleaseMode: true), isFalse);
      expect(resolveLoggingEnabled(true, isReleaseMode: true), isTrue);
    });

    test('logging is on in debug builds unless explicitly disabled', () {
      expect(resolveLoggingEnabled(null, isReleaseMode: false), isTrue);
      expect(resolveLoggingEnabled(false, isReleaseMode: false), isFalse);
    });

    test('tests run in debug mode, so the default config is enabled', () {
      expect(const NetworkLoggerConfig().isEnabled, isTrue);
      expect(const NetworkLoggerConfig(enabled: false).isEnabled, isFalse);
    });
  });

  test('isExcluded matches substrings and regular expressions', () {
    final config = NetworkLoggerConfig(
      excludedUrls: ['/health', RegExp(r'analytics\.example\.com')],
    );
    expect(config.isExcluded(Uri.parse('https://a.dev/health?x=1')), isTrue);
    expect(
      config.isExcluded(Uri.parse('https://analytics.example.com/e')),
      isTrue,
    );
    expect(config.isExcluded(Uri.parse('https://a.dev/users')), isFalse);
  });
}
