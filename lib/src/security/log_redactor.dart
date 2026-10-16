/// Replaces sensitive values in headers, URLs, structured data and text.
///
/// A key is sensitive when its normalized form (lower-case, without `-`,
/// `_`, `.` or spaces) contains one of [defaultSensitiveFragments], equals one
/// of [defaultSensitiveKeys], or equals one of the configured extra keys.
class LogRedactor {
  /// Creates a redactor with optional [extraKeys] and a custom [mask].
  LogRedactor({Iterable<String> extraKeys = const [], this.mask = '***'})
      : _extraKeys = {for (final key in extraKeys) _normalize(key)};

  /// Key fragments that mark a key as sensitive wherever they appear,
  /// e.g. `access_token`, `X-Api-Key`, `newPassword`.
  static const List<String> defaultSensitiveFragments = [
    'authorization',
    'cookie',
    'password',
    'passwd',
    'passphrase',
    'secret',
    'token',
    'apikey',
    'credential',
    'session',
    'privatekey',
  ];

  /// Short keys that are sensitive only on an exact (normalized) match.
  static const Set<String> defaultSensitiveKeys = {
    'otp',
    'otpcode',
    'pin',
    'pwd',
    'cvv',
    'cvc',
    'ssn',
    'auth',
    'jwt',
    'signature',
    'sig',
  };

  /// The replacement for redacted values.
  final String mask;

  final Set<String> _extraKeys;

  /// Maximum nesting depth processed by [redactValue].
  static const int maxDepth = 32;

  /// Whether values stored under [key] must be redacted.
  bool isSensitiveKey(String key) {
    final normalized = _normalize(key);
    if (normalized.isEmpty) return false;
    return _extraKeys.contains(normalized) ||
        defaultSensitiveKeys.contains(normalized) ||
        defaultSensitiveFragments.any(normalized.contains);
  }

  /// Returns a copy of [headers] with sensitive values masked.
  Map<String, String> redactHeaders(Map<String, String> headers) => {
        for (final entry in headers.entries)
          entry.key: isSensitiveKey(entry.key) ? mask : entry.value,
      };

  /// Returns [url] with credentials and sensitive query values masked.
  Uri redactUrl(Uri url) {
    var result = url;
    if (result.userInfo.isNotEmpty) {
      result = result.replace(userInfo: mask);
    }
    if (result.hasQuery && result.query.isNotEmpty) {
      final params = result.queryParametersAll;
      if (params.keys.any(isSensitiveKey)) {
        result = result.replace(queryParameters: {
          for (final entry in params.entries)
            entry.key: isSensitiveKey(entry.key)
                ? List.filled(entry.value.length, mask)
                : entry.value,
        });
      }
    }
    return result;
  }

  /// Returns a redacted, JSON-compatible copy of [value].
  ///
  /// Maps and lists are copied recursively; sensitive map keys have their
  /// values masked. Strings, numbers, booleans and `null` are kept. Anything
  /// else is replaced by a placeholder naming its type, so objects whose
  /// `toString` could expose secrets are never stringified.
  Object? redactValue(Object? value, [int depth = 0]) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) return value;
    if (depth >= maxDepth) return '<max depth>';
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': isSensitiveKey('${entry.key}')
              ? mask
              : redactValue(entry.value, depth + 1),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) redactValue(item, depth + 1)];
    }
    return '<${value.runtimeType}>';
  }

  static final RegExp _jsonPair = RegExp(
    r'"([^"\\]{1,100})"(\s*:\s*)("(?:[^"\\]|\\.)*"?|[^,}\]\s]+)',
  );
  static final RegExp _formPair = RegExp(r'([\w.\-\[\]]{1,100})=([^&\s]*)');
  static final RegExp _bearer =
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false);

  /// Masks sensitive values in unstructured [text].
  ///
  /// Used for bodies that could not be parsed (for example truncated JSON),
  /// form-encoded bodies and error messages. Handles `"key": value` pairs,
  /// `key=value` pairs and bearer/basic credentials.
  String redactText(String text) {
    var result = text.replaceAllMapped(_jsonPair, (m) {
      final key = m.group(1)!;
      if (!isSensitiveKey(key)) return m.group(0)!;
      return '"$key"${m.group(2)}"$mask"';
    });
    result = result.replaceAllMapped(_formPair, (m) {
      final key = m.group(1)!;
      return isSensitiveKey(key) ? '$key=$mask' : m.group(0)!;
    });
    return result.replaceAllMapped(_bearer, (m) => '${m.group(1)} $mask');
  }

  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[\s\-_.]'), '');
}
