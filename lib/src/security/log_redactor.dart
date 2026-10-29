import 'dart:convert';

/// Replaces sensitive values in headers, URLs, structured data and text.
///
/// A key is sensitive when its normalized form (lower-case, without `-`,
/// `_`, `.` or spaces) contains one of [defaultSensitiveFragments], equals one
/// of [defaultSensitiveKeys], or equals one of the configured extra keys.
/// Extra keys can be scoped to headers ([headerKeys]), query parameters
/// ([queryKeys]) or body keys ([bodyKeys]); [extraKeys] apply everywhere.
///
/// Values stored under non-sensitive keys are still scanned for
/// self-identifying secrets: `Bearer`/`Basic` credentials, JSON Web Tokens
/// and credentials embedded in URLs.
class LogRedactor {
  /// Creates a redactor with optional extra keys and a custom [mask].
  LogRedactor({
    Iterable<String> extraKeys = const [],
    Iterable<String> headerKeys = const [],
    Iterable<String> queryKeys = const [],
    Iterable<String> bodyKeys = const [],
    this.mask = '***',
  })  : _extraKeys = _normalizeAll(extraKeys),
        _headerKeys = _normalizeAll(headerKeys),
        _queryKeys = {
          ..._normalizeAll(queryKeys),
          ...defaultSensitiveQueryParameters,
        },
        _bodyKeys = _normalizeAll(bodyKeys);

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

  /// Query parameter names that are sensitive in URLs only (exact,
  /// normalized match). `key` carries API keys in many public APIs
  /// (`?key=AIza…`) but is too common as a body key to redact everywhere.
  static const Set<String> defaultSensitiveQueryParameters = {'key'};

  /// The replacement for redacted values.
  final String mask;

  final Set<String> _extraKeys;
  final Set<String> _headerKeys;
  final Set<String> _queryKeys;
  final Set<String> _bodyKeys;

  /// Maximum nesting depth processed by [redactValue].
  static const int maxDepth = 32;

  /// Strings longer than this are not parsed as embedded JSON documents;
  /// they are redacted by pattern.
  static const int embeddedParseLimit = 64 * 1024;

  /// Whether values stored under [key] must be redacted in every context.
  bool isSensitiveKey(String key) {
    final normalized = _normalize(key);
    if (normalized.isEmpty) return false;
    return _extraKeys.contains(normalized) ||
        defaultSensitiveKeys.contains(normalized) ||
        defaultSensitiveFragments.any(normalized.contains);
  }

  /// Whether the header [name] must be redacted.
  bool isSensitiveHeader(String name) =>
      isSensitiveKey(name) || _headerKeys.contains(_normalize(name));

  /// Whether the query parameter [name] must be redacted.
  bool isSensitiveQueryParameter(String name) =>
      isSensitiveKey(name) || _queryKeys.contains(_normalize(name));

  /// Whether a body key (JSON, form, multipart, XML or GraphQL) must be
  /// redacted.
  bool isSensitiveBodyKey(String key) =>
      isSensitiveKey(key) || _bodyKeys.contains(_normalize(key));

  /// Text of unknown origin (error messages, unparseable bodies) may hold
  /// any kind of key, so every scope applies.
  bool _isSensitiveTextKey(String key) {
    final normalized = _normalize(key);
    return isSensitiveKey(key) ||
        _headerKeys.contains(normalized) ||
        _queryKeys.contains(normalized) ||
        _bodyKeys.contains(normalized);
  }

  /// Returns a copy of [headers] with sensitive values masked. Other values
  /// are scanned for credentials with [redactText].
  Map<String, String> redactHeaders(Map<String, String> headers) => {
        for (final entry in headers.entries)
          entry.key:
              isSensitiveHeader(entry.key) ? mask : redactText(entry.value),
      };

  /// Returns [url] with credentials and sensitive values masked: user info,
  /// sensitive query parameters, secrets inside other query values (such as
  /// GraphQL `variables`), the fragment (`#access_token=…`) and JSON Web
  /// Tokens in the path. Returns [url] itself when nothing is sensitive.
  Uri redactUrl(Uri url) {
    var result = url;
    if (result.userInfo.isNotEmpty) {
      result = result.replace(userInfo: mask);
    }
    if (result.hasQuery && result.query.isNotEmpty) {
      final params = result.queryParametersAll;
      var changed = false;
      final redacted = <String, List<String>>{
        for (final entry in params.entries)
          entry.key: [
            for (final value in entry.value)
              _track(
                value,
                isSensitiveQueryParameter(entry.key)
                    ? mask
                    : redactString(value),
                () => changed = true,
              ),
          ],
      };
      if (changed) result = result.replace(queryParameters: redacted);
    }
    if (result.hasFragment && result.fragment.isNotEmpty) {
      final fragment = redactText(result.fragment);
      if (fragment != result.fragment) {
        result = result.replace(fragment: fragment);
      }
    }
    if (_jwt.hasMatch(result.path)) {
      result = result.replace(path: result.path.replaceAll(_jwt, mask));
    }
    return result;
  }

  static String _track(String before, String after, void Function() onChange) {
    if (after != before) onChange();
    return after;
  }

  /// Returns a redacted, JSON-compatible copy of [value].
  ///
  /// Maps and lists are copied recursively; sensitive map keys have their
  /// values masked. Strings are scanned with [redactString]; numbers,
  /// booleans and `null` are kept. Anything else is replaced by a
  /// placeholder naming its type, so objects whose `toString` could expose
  /// secrets are never stringified.
  Object? redactValue(Object? value, [int depth = 0]) {
    if (value == null || value is num || value is bool) return value;
    if (value is String) return redactString(value, depth);
    if (depth >= maxDepth) return '<max depth>';
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': isSensitiveBodyKey('${entry.key}')
              ? mask
              : redactValue(entry.value, depth + 1),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) redactValue(item, depth + 1)];
    }
    return '<${value.runtimeType}>';
  }

  /// Every pattern of [redactText] needs one of these, so strings without
  /// them are returned unchanged without running the patterns.
  static final RegExp _mayHoldSecret =
      RegExp(r'[=:]|eyJ|Bearer|Basic', caseSensitive: false);

  /// Redacts a string stored under a non-sensitive key.
  ///
  /// An embedded JSON object or array (for example a stringified payload or
  /// a multipart `operations` field) is parsed and redacted by key; other
  /// text is redacted by pattern with [redactText]. The original string is
  /// returned when nothing is sensitive.
  String redactString(String value, [int depth = 0]) {
    if (value.isEmpty || !_mayHoldSecret.hasMatch(value)) return value;
    final start = value.trimLeft();
    if ((start.startsWith('{') || start.startsWith('[')) &&
        value.length <= embeddedParseLimit &&
        depth < maxDepth) {
      try {
        final decoded = jsonDecode(value);
        final redacted = redactValue(decoded, depth + 1);
        final encoded = jsonEncode(redacted);
        return encoded == jsonEncode(decoded) ? value : encoded;
      } on FormatException {
        // Not JSON after all; redact by pattern.
      }
    }
    return redactText(value);
  }

  static final RegExp _jsonKey = RegExp(r'"([^"\\]{1,100})"\s*:\s*');
  static final RegExp _formKey =
      RegExp(r'(?<![\w.\-\[\]%+])([\w.\-\[\]%+]{1,100})=');
  static final RegExp _textKey =
      RegExp(r'''(?<![\w"'.\-\[\]%])([A-Za-z_][\w.\-]{0,99})[ \t]*:[ \t]*''');
  static final RegExp _bearer =
      RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9\-._~+/]+=*', caseSensitive: false);
  static final RegExp _jwt =
      RegExp(r'\beyJ[A-Za-z0-9_-]{2,}\.eyJ[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]*');
  static final RegExp _urlCredentials =
      RegExp(r'\b([A-Za-z][A-Za-z0-9+.\-]*://)[^\s/@?#]+@');

  /// Masks sensitive values in unstructured [text].
  ///
  /// Used for bodies that could not be parsed (for example truncated JSON),
  /// form-encoded bodies, header values and error messages. Handles
  /// `"key": value` pairs (masking whole objects and arrays, even when they
  /// are cut off), `key=value` pairs (including percent-encoded keys),
  /// `key: value` pairs, `Bearer`/`Basic` credentials, JSON Web Tokens and
  /// URL user info.
  String redactText(String text) {
    if (!_mayHoldSecret.hasMatch(text)) return text;
    var result = _redactCredentials(text);
    if (!result.contains(':') && !result.contains('=')) return result;
    result = _redactPairs(
      result,
      _jsonKey,
      _isSensitiveTextKey,
      _jsonValueEnd,
      '"$mask"',
    );
    result = _redactPairs(
      result,
      _formKey,
      (key) => _isSensitiveTextKey(_decodeFormKey(key)),
      _formValueEnd,
      mask,
    );
    return _redactPairs(
      result,
      _textKey,
      _isSensitiveTextKey,
      _textValueEnd,
      mask,
    );
  }

  String _redactCredentials(String text) => text
      .replaceAll(_jwt, mask)
      .replaceAllMapped(_bearer, (m) => '${m.group(1)} $mask')
      .replaceAllMapped(_urlCredentials, (m) => '${m.group(1)}$mask@');

  /// Replaces the value following each sensitive key matched by [key]. The
  /// value ends where [valueEnd] says; keys inside a masked value are
  /// skipped.
  String _redactPairs(
    String text,
    RegExp key,
    bool Function(String key) isSensitive,
    int Function(String text, int start) valueEnd,
    String replacement,
  ) {
    StringBuffer? out;
    var copied = 0;
    for (final match in key.allMatches(text)) {
      if (match.start < copied || !isSensitive(match.group(1)!)) continue;
      final end = valueEnd(text, match.end);
      if (end == match.end) continue;
      (out ??= StringBuffer())
        ..write(text.substring(copied, match.end))
        ..write(replacement);
      copied = end;
    }
    if (out == null) return text;
    return (out..write(text.substring(copied))).toString();
  }

  static String _decodeFormKey(String key) {
    try {
      return Uri.decodeQueryComponent(key);
    } catch (_) {
      return key;
    }
  }

  /// The end of a JSON value starting at [start]. Strings, objects and
  /// arrays that are cut off extend to the end of [text].
  static int _jsonValueEnd(String text, int start) {
    if (start >= text.length) return start;
    final first = text[start];
    if (first == '"') return _stringEnd(text, start, '"');
    if (first == '{' || first == '[') {
      var depth = 0;
      for (var i = start; i < text.length; i++) {
        final char = text[i];
        if (char == '"') {
          i = _stringEnd(text, i, '"') - 1;
        } else if (char == '{' || char == '[') {
          depth++;
        } else if (char == '}' || char == ']') {
          if (--depth == 0) return i + 1;
        }
      }
      return text.length;
    }
    return _scan(text, start, ',}] \t\r\n');
  }

  /// Form values are percent-encoded, so these characters end them.
  static int _formValueEnd(String text, int start) =>
      _scan(text, start, '& \t\r\n"\';#<>');

  static final RegExp _scheme =
      RegExp(r'(?:Bearer|Basic)\s+', caseSensitive: false);

  static int _textValueEnd(String text, int start) {
    if (start >= text.length) return start;
    final first = text[start];
    if (first == '"' || first == "'") return _stringEnd(text, start, first);
    final scheme = _scheme.matchAsPrefix(text, start);
    return _scan(text, scheme?.end ?? start, ' \t\r\n,;&)}]"\'<>');
  }

  /// The index after the closing [quote] of the string opening at [start],
  /// or the end of [text] when it is cut off.
  static int _stringEnd(String text, int start, String quote) {
    for (var i = start + 1; i < text.length; i++) {
      final char = text[i];
      if (char == r'\') {
        i++;
      } else if (char == quote) {
        return i + 1;
      }
    }
    return text.length;
  }

  static int _scan(String text, int start, String stops) {
    var i = start;
    while (i < text.length && !stops.contains(text[i])) {
      i++;
    }
    return i;
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
  /// (`<input name="csrf_token" value="…">`), plus bearer credentials and
  /// JSON Web Tokens.
  String redactMarkup(String text) {
    var result = text.replaceAllMapped(_element, (m) {
      if (!isSensitiveBodyKey(m.group(2)!) || m.group(4)!.trim().isEmpty) {
        return m.group(0)!;
      }
      return '<${m.group(1)}${m.group(3) ?? ''}>$mask${m.group(5)}';
    });
    result = result.replaceAllMapped(_tag, (tag) => _redactTag(tag.group(0)!));
    return _redactCredentials(result);
  }

  String _redactTag(String tag) {
    final attributes = {
      for (final m in _attribute.allMatches(tag))
        m.group(1)!.toLowerCase(): _unquote(m.group(3)!),
    };
    final namedSensitive = isSensitiveBodyKey(attributes['name'] ?? '') ||
        isSensitiveBodyKey(attributes['id'] ?? '');
    return tag.replaceAllMapped(_attribute, (m) {
      final name = m.group(1)!;
      final localName = name.contains(':') ? name.split(':').last : name;
      final masked = isSensitiveBodyKey(localName) ||
          (namedSensitive && localName.toLowerCase() == 'value');
      if (!masked) return m.group(0)!;
      final quote = m.group(3)![0];
      return '$name${m.group(2)}$quote$mask$quote';
    });
  }

  static String _unquote(String value) => value.substring(1, value.length - 1);

  static Set<String> _normalizeAll(Iterable<String> keys) => {
        for (final key in keys) _normalize(key),
      }..remove('');

  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[\s\-_.]'), '');
}
