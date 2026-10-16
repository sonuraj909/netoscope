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
    'signature',
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

  static final RegExp _element = RegExp(
    r'<((?:[\w.\-]+:)?([\w.\-]+))(\s[^<>]*)?>([^<]*)(</\1\s*>|$)',
  );
  static final RegExp _tag = RegExp(r'<[A-Za-z][^<>]*>');
  static final RegExp _attribute =
      RegExp(r'''([\w.:\-]+)(\s*=\s*)("[^"]*"|'[^']*')''');

  /// Masks sensitive values in XML or HTML [text].
  ///
  /// Handles element text (`<password>…</password>`), attributes
  /// (`token="…"`) and form inputs whose `name`/`id` is sensitive
  /// (`<input name="csrf_token" value="…">`), plus bearer credentials.
  String redactMarkup(String text) {
    var result = text.replaceAllMapped(_element, (m) {
      if (!isSensitiveKey(m.group(2)!) || m.group(4)!.trim().isEmpty) {
        return m.group(0)!;
      }
      return '<${m.group(1)}${m.group(3) ?? ''}>$mask${m.group(5)}';
    });
    result = result.replaceAllMapped(_tag, (tag) => _redactTag(tag.group(0)!));
    return result.replaceAllMapped(_bearer, (m) => '${m.group(1)} $mask');
  }

  String _redactTag(String tag) {
    final attributes = {
      for (final m in _attribute.allMatches(tag))
        m.group(1)!.toLowerCase(): _unquote(m.group(3)!),
    };
    final namedSensitive = isSensitiveKey(attributes['name'] ?? '') ||
        isSensitiveKey(attributes['id'] ?? '');
    return tag.replaceAllMapped(_attribute, (m) {
      final name = m.group(1)!;
      final localName = name.contains(':') ? name.split(':').last : name;
      final masked = isSensitiveKey(localName) ||
          (namedSensitive && localName.toLowerCase() == 'value');
      if (!masked) return m.group(0)!;
      final quote = m.group(3)![0];
      return '$name${m.group(2)}$quote$mask$quote';
    });
  }

  static String _unquote(String value) => value.substring(1, value.length - 1);

  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[\s\-_.]'), '');
}
