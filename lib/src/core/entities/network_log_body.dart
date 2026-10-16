import 'json_helpers.dart';
import 'payload_format.dart';

/// How a captured payload is represented in [NetworkLogBody.content].
///
/// This is the coarse rendering category. See [NetworkLogBody.format] for the
/// detected format (XML, HTML, form, protobuf, …).
enum NetworkBodyKind {
  /// Structured JSON (from a map, a list, a JSON string or a decoder).
  json,

  /// Text, including XML, HTML and form-encoded bodies.
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
  ///
  /// When [format] is omitted it is derived from [kind].
  const NetworkLogBody({
    required this.kind,
    required this.content,
    this.isTruncated = false,
    PayloadFormat? format,
    this.contentType,
  }) : _format = format;

  /// Restores a body from [toJson] output.
  factory NetworkLogBody.fromJson(Map<String, Object?> json) => NetworkLogBody(
        kind: readEnum(
            NetworkBodyKind.values, json['kind'], NetworkBodyKind.text),
        content: readAs<String>(json['content']) ?? '',
        isTruncated: json['truncated'] == true,
        format: json['format'] is String
            ? PayloadFormat.byId(json['format']! as String)
            : null,
        contentType: readAs<String>(json['contentType']),
      );

  /// How [content] is represented.
  final NetworkBodyKind kind;

  /// Redacted text, possibly truncated. For [NetworkBodyKind.json] this is
  /// compact JSON unless [isTruncated] is `true`. For binary, stream and
  /// unsupported payloads it is a short placeholder description.
  final String content;

  /// Whether [content] was cut at the configured size limit.
  final bool isTruncated;

  /// The declared content type, if any.
  final String? contentType;

  final PayloadFormat? _format;

  /// The detected or decoded payload format.
  PayloadFormat get format =>
      _format ??
      switch (kind) {
        NetworkBodyKind.json => PayloadFormat.json,
        NetworkBodyKind.text => PayloadFormat.text,
        NetworkBodyKind.multipart => PayloadFormat.multipart,
        NetworkBodyKind.binary => PayloadFormat.binary,
        NetworkBodyKind.stream => PayloadFormat.stream,
        NetworkBodyKind.unsupported => PayloadFormat.unsupported,
      };

  /// A JSON-compatible representation of this body.
  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'format': format.id,
        'contentType': contentType,
        'content': content,
        'truncated': isTruncated,
      };

  @override
  bool operator ==(Object other) =>
      other is NetworkLogBody &&
      other.kind == kind &&
      other.format == format &&
      other.content == content &&
      other.isTruncated == isTruncated &&
      other.contentType == contentType;

  @override
  int get hashCode =>
      Object.hash(kind, format, content, isTruncated, contentType);
}
