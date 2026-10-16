/// How a captured payload was interpreted.
enum NetworkBodyKind {
  /// Structured JSON (from a map, a list or a JSON string).
  json,

  /// Plain or form-encoded text.
  text,

  /// A multipart form. [NetworkLogBody.content] describes the fields and
  /// file metadata, never file contents.
  multipart,

  /// Binary data. Only the size is recorded.
  binary,

  /// A stream that was not read, to avoid consuming it.
  stream,

  /// An object that could not be serialized safely.
  unsupported,
}

/// An immutable, already-redacted snapshot of a request or response body.
class NetworkLogBody {
  /// Creates a body snapshot.
  const NetworkLogBody({
    required this.kind,
    required this.content,
    this.isTruncated = false,
  });

  /// How the payload was interpreted.
  final NetworkBodyKind kind;

  /// Redacted text, possibly truncated. For [NetworkBodyKind.json] this is
  /// compact JSON unless [isTruncated] is `true`. For binary, stream and
  /// unsupported payloads it is a short placeholder description.
  final String content;

  /// Whether [content] was cut at the configured size limit.
  final bool isTruncated;

  /// A JSON-compatible representation of this body.
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'content': content,
        'truncated': isTruncated,
      };

  @override
  bool operator ==(Object other) =>
      other is NetworkLogBody &&
      other.kind == kind &&
      other.content == content &&
      other.isTruncated == isTruncated;

  @override
  int get hashCode => Object.hash(kind, content, isTruncated);
}
