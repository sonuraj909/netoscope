import 'dart:convert';

import '../../core/entities/graphql_details.dart';
import '../../security/log_redactor.dart';

/// Recognizes GraphQL operations in HTTP (and WebSocket) payloads and
/// summarizes GraphQL responses.
///
/// Works on payloads that are already available to the adapters; it never
/// reads streams. Every value it returns is redacted.
class GraphQLInspector {
  /// Creates an inspector. Documents and variables are cut to
  /// [maxTextLength] characters.
  const GraphQLInspector({
    required LogRedactor redactor,
    required this.maxTextLength,
  }) : _redactor = redactor;

  final LogRedactor _redactor;

  /// The maximum length of captured documents and variables.
  final int maxTextLength;

  /// Payloads larger than this are not parsed.
  static const int parseLimit = 1024 * 1024;

  /// Inspects an HTTP exchange. Returns `null` unless the request carries
  /// GraphQL operations.
  ///
  /// [requestBody] and [responseBody] may be maps, lists, JSON strings or
  /// UTF-8 bytes. For GET requests the operation is read from [url].
  GraphQLDetails? inspectHttp({
    required String method,
    required Uri url,
    String? requestContentType,
    Object? requestBody,
    Object? responseBody,
  }) {
    final operations = _operationsFromRequest(
      method,
      url,
      requestContentType,
      requestBody,
    );
    if (operations == null || operations.isEmpty) return null;
    final response = _parse(responseBody);
    return GraphQLDetails(
      operations: operations,
      errors: _errorsFrom(response),
      hasData: response == null ? null : _hasData(response),
    );
  }

  /// Parses one operation from a `{query, operationName, variables,
  /// extensions}` map, or returns `null` if [payload] is not one.
  GraphQLOperation? operationFrom(Object? payload) {
    if (payload is! Map) return null;
    final query = payload['query'];
    final hash = _persistedHash(payload['extensions']);
    if (query is String) {
      if (!looksLikeDocument(query)) return null;
    } else if (hash == null) {
      return null;
    }
    final declaredName = payload['operationName'];
    return _operation(
      document: query is String ? query : null,
      operationName: declaredName is String ? declaredName : null,
      variables: payload['variables'],
      persistedQueryHash: hash,
    );
  }

  /// Extracts GraphQL errors from a response payload (a map, or a list of
  /// maps for batches).
  List<GraphQLError> errorsFrom(Object? response) => _errorsFrom(response);

  static final RegExp _documentStart = RegExp(
    r'^\s*(?:#[^\n]*\n\s*)*(?:\{|(?:query|mutation|subscription|fragment)\b)',
  );

  /// Whether [text] looks like a GraphQL document rather than, say, a search
  /// term sent under a `query` key.
  static bool looksLikeDocument(String text) => _documentStart.hasMatch(text);

  List<GraphQLOperation>? _operationsFromRequest(
    String method,
    Uri url,
    String? contentType,
    Object? body,
  ) {
    final type = contentType?.toLowerCase() ?? '';
    if (type.startsWith('application/graphql') && !type.contains('json')) {
      final document = _text(body);
      if (document == null || !looksLikeDocument(document)) return null;
      return [_operation(document: document)];
    }
    if (method.toUpperCase() == 'GET') {
      final params = url.queryParameters;
      final query = params['query'];
      Object? extensions;
      try {
        final raw = params['extensions'];
        extensions = raw == null ? null : jsonDecode(raw);
      } on FormatException {
        extensions = null;
      }
      final hash = _persistedHash(extensions);
      if ((query == null || !looksLikeDocument(query)) && hash == null) {
        return null;
      }
      Object? variables;
      try {
        final raw = params['variables'];
        variables = raw == null ? null : jsonDecode(raw);
      } on FormatException {
        variables = params['variables'];
      }
      return [
        _operation(
          document: query,
          operationName: params['operationName'],
          variables: variables,
          persistedQueryHash: hash,
        ),
      ];
    }
    final payload = _parse(body);
    if (payload is Map) {
      final operation = operationFrom(payload);
      return operation == null ? null : [operation];
    }
    if (payload is List && payload.isNotEmpty) {
      final operations = [for (final item in payload) operationFrom(item)];
      if (operations.any((op) => op == null)) return null;
      return operations.cast<GraphQLOperation>();
    }
    return null;
  }

  GraphQLOperation _operation({
    String? document,
    String? operationName,
    Object? variables,
    String? persistedQueryHash,
  }) {
    final cleaned = document == null ? null : _stripComments(document);
    final (type, name) = cleaned == null
        ? (GraphQLOperationType.unknown, operationName)
        : _identify(cleaned, operationName);
    return GraphQLOperation(
      name: name,
      type: type,
      document: document == null ? null : _cut(_redactDocument(document)),
      variables: variables == null
          ? null
          : _cut(jsonEncode(_redactor.redactValue(variables))),
      persistedQueryHash: persistedQueryHash,
    );
  }

  static final RegExp _definition = RegExp(
    r'(?:^|\})\s*(query|mutation|subscription)\b\s*([_A-Za-z][_0-9A-Za-z]*)?',
  );

  static (GraphQLOperationType, String?) _identify(
    String document,
    String? operationName,
  ) {
    final definitions = _definition.allMatches(document).toList();
    if (operationName != null) {
      for (final match in definitions) {
        if (match.group(2) == operationName) {
          return (_type(match.group(1)!), operationName);
        }
      }
    }
    if (document.trimLeft().startsWith('{')) {
      return (GraphQLOperationType.query, operationName);
    }
    if (definitions.isEmpty) {
      return (GraphQLOperationType.unknown, operationName);
    }
    final first = definitions.first;
    return (_type(first.group(1)!), operationName ?? first.group(2));
  }

  static GraphQLOperationType _type(String keyword) => switch (keyword) {
        'mutation' => GraphQLOperationType.mutation,
        'subscription' => GraphQLOperationType.subscription,
        _ => GraphQLOperationType.query,
      };

  static String _stripComments(String document) =>
      document.replaceAll(RegExp(r'#[^\n]*'), '');

  static final RegExp _inlineArgument = RegExp(
    r'([_A-Za-z][_0-9A-Za-z]*)(\s*:\s*)("""[\s\S]*?"""|"(?:[^"\\]|\\.)*"|-?\d[\d.eE+\-]*)',
  );

  /// Masks literal values of sensitive inline arguments, such as
  /// `login(password: "hunter2")`. Variable references are left alone.
  String _redactDocument(String document) =>
      document.replaceAllMapped(_inlineArgument, (m) {
        if (!_redactor.isSensitiveKey(m.group(1)!)) return m.group(0)!;
        return '${m.group(1)}${m.group(2)}"${_redactor.mask}"';
      });

  static String? _persistedHash(Object? extensions) {
    if (extensions is! Map) return null;
    final persisted = extensions['persistedQuery'];
    if (persisted is! Map) return null;
    final hash = persisted['sha256Hash'];
    return hash is String ? hash : null;
  }

  static const int _maxErrors = 50;

  List<GraphQLError> _errorsFrom(Object? response) {
    final errors = <GraphQLError>[];
    void collect(Object? payload, int? index) {
      if (payload is! Map) return;
      final list = payload['errors'];
      if (list is! List) return;
      for (final item in list) {
        if (errors.length >= _maxErrors) return;
        if (item is! Map) continue;
        final message = item['message'];
        final path = item['path'];
        final extensions = item['extensions'];
        final code = extensions is Map ? extensions['code'] : null;
        errors.add(
          GraphQLError(
            message: _redactor.redactText(
              message is String ? message : 'Unknown error',
            ),
            path: [
              if (path is List)
                for (final segment in path)
                  if (segment is String || segment is int) segment as Object,
            ],
            code: code is String ? code : null,
            operationIndex: index,
          ),
        );
      }
    }

    if (response is List) {
      for (var i = 0; i < response.length; i++) {
        collect(response[i], i);
      }
    } else {
      collect(response, null);
    }
    return errors;
  }

  static bool _hasData(Object response) {
    bool check(Object? payload) => payload is Map && payload['data'] != null;
    return response is List ? response.any(check) : check(response);
  }

  static String? _text(Object? body) {
    if (body is String) return body;
    if (body is List<int> && body.length <= parseLimit) {
      return utf8.decode(body, allowMalformed: true);
    }
    return null;
  }

  static Object? _parse(Object? body) {
    if (body is Map || body is List && body is! List<int>) return body;
    final text = _text(body);
    if (text == null || text.length > parseLimit) return null;
    final trimmed = text.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  String _cut(String text) => text.length <= maxTextLength
      ? text
      : '${text.substring(0, maxTextLength)}…';
}
