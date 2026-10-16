import 'protocol_details.dart';

/// The kind of a GraphQL operation.
enum GraphQLOperationType {
  /// A `query` (or the `{ … }` shorthand).
  query,

  /// A `mutation`.
  mutation,

  /// A `subscription`.
  subscription,

  /// Not identifiable, for example a persisted query sent by hash only.
  unknown,
}

/// One GraphQL operation from a request (batches contain several).
class GraphQLOperation {
  /// Creates an operation description. Values must already be redacted.
  const GraphQLOperation({
    this.name,
    this.type = GraphQLOperationType.unknown,
    this.document,
    this.variables,
    this.persistedQueryHash,
  });

  /// The operation name, if given or found in the document.
  final String? name;

  /// The operation type.
  final GraphQLOperationType type;

  /// The (redacted, possibly truncated) query document.
  final String? document;

  /// The (redacted) variables as compact JSON.
  final String? variables;

  /// The SHA-256 hash of an automatic persisted query.
  final String? persistedQueryHash;

  /// `name` if present, otherwise the type, such as `query`.
  String get displayName => name ?? type.name;

  /// A JSON-compatible representation.
  Map<String, Object?> toJson() => {
        'name': name,
        'type': type.name,
        'document': document,
        'variables': variables,
        'persistedQueryHash': persistedQueryHash,
      };
}

/// One entry from a GraphQL response's `errors` array.
class GraphQLError {
  /// Creates an error description. [message] must already be redacted.
  GraphQLError({
    required this.message,
    List<Object> path = const [],
    this.code,
    this.operationIndex,
  }) : path = List.unmodifiable(path);

  /// The error message.
  final String message;

  /// The `path` to the failing field: names and list indices.
  final List<Object> path;

  /// `extensions.code`, when present.
  final String? code;

  /// For batched requests, the index of the operation that failed.
  final int? operationIndex;

  /// [path] joined with dots, such as `user.posts.0.title`.
  String get pathLabel => path.join('.');

  /// A JSON-compatible representation.
  Map<String, Object?> toJson() => {
        'message': message,
        'path': path,
        'code': code,
        'operationIndex': operationIndex,
      };
}

/// GraphQL information for a call carrying one or more operations.
///
/// The HTTP outcome of the entry reflects the transport only. Execution
/// errors are reported here: a `200 OK` response can still contain [errors],
/// with or without partial data.
class GraphQLDetails extends ProtocolDetails {
  /// Creates GraphQL details.
  GraphQLDetails({
    required List<GraphQLOperation> operations,
    List<GraphQLError> errors = const [],
    this.hasData,
  })  : operations = List.unmodifiable(operations),
        errors = List.unmodifiable(errors);

  /// The operations sent. More than one for batched requests.
  final List<GraphQLOperation> operations;

  /// Execution errors from the response.
  final List<GraphQLError> errors;

  /// Whether the response contained non-null `data`; `null` when the
  /// response was not available or not parsed.
  final bool? hasData;

  /// Whether several operations were sent in one request.
  bool get isBatch => operations.length > 1;

  /// Whether the response reported execution errors.
  bool get hasErrors => errors.isNotEmpty;

  /// Whether the response contained both data and errors.
  bool get isPartial => (hasData ?? false) && hasErrors;

  /// The first operation's display name, or `batch (n)`.
  String get summary => isBatch
      ? 'batch (${operations.length})'
      : operations.isEmpty
          ? 'operation'
          : '${operations.first.type.name} ${operations.first.displayName}'
              .trim();

  @override
  String get type => 'graphql';

  @override
  String get label => 'GraphQL';

  @override
  Map<String, String> describe() => {
        'Operation': summary,
        'Errors': '${errors.length}',
        if (hasData != null) 'Data': hasData! ? 'present' : 'none',
        if (isPartial) 'Result': 'partial data with errors',
      };

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'operations': [for (final op in operations) op.toJson()],
        'errors': [for (final error in errors) error.toJson()],
        'hasData': hasData,
      };
}
