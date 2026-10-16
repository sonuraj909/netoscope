import 'dart:typed_data';

import '../entities/network_event_kind.dart';
import '../entities/payload_format.dart';

/// Where a payload was observed. Passed to [PayloadDecoder]s so they can
/// choose a schema by endpoint, content type or direction.
class PayloadContext {
  /// Creates a payload context.
  const PayloadContext({
    this.contentType,
    this.url,
    this.direction = MessageDirection.incoming,
    this.protocol = NetworkProtocol.http,
  });

  /// The declared content type, if any.
  final String? contentType;

  /// The request or connection URL (not yet redacted), if known.
  final Uri? url;

  /// [MessageDirection.outgoing] for requests and sent messages,
  /// [MessageDirection.incoming] for responses and received messages.
  final MessageDirection direction;

  /// The protocol the payload belongs to.
  final NetworkProtocol protocol;
}

/// Turns raw payload bytes into an inspectable value.
///
/// Register decoders with `NetworkLoggerConfig.payloadDecoders`. They run
/// before redaction and truncation, on complete payloads only, and are tried
/// in order until one returns a non-null value. A decoder that throws is
/// skipped. Decoders must not keep references to the bytes they receive.
abstract interface class PayloadDecoder {
  /// The format reported for payloads this decoder handles.
  PayloadFormat get format;

  /// Whether this decoder should handle a payload seen in [context].
  bool canDecode(PayloadContext context);

  /// Decodes [bytes].
  ///
  /// Return a JSON-compatible structure (maps with string keys, lists,
  /// strings, numbers, booleans, `null`), which is then redacted by key, or
  /// a [String], which is redacted by pattern. Return `null` to let the next
  /// decoder or the built-in handling take over.
  Object? decode(Uint8List bytes, PayloadContext context);
}
