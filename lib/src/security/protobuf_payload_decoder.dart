import 'dart:typed_data';

import '../core/contracts/payload_decoder.dart';
import '../core/entities/payload_format.dart';
import '../protocols/grpc/grpc_frames.dart';

/// Decodes Protocol Buffers payloads with a decoder you provide.
///
/// Netoscope has no protobuf dependency and cannot decode protobuf without a
/// schema. Supply [decode] using your generated classes, for example:
///
/// ```dart
/// ProtobufPayloadDecoder(
///   decode: (bytes, context) => switch (context.url?.path) {
///     '/helloworld.Greeter/SayHello' => context.direction ==
///             MessageDirection.outgoing
///         ? HelloRequest.fromBuffer(bytes).toProto3Json()
///         : HelloReply.fromBuffer(bytes).toProto3Json(),
///     _ => null,
///   },
/// )
/// ```
///
/// gRPC and gRPC-Web bodies are split into frames first; [decode] receives
/// one message at a time. Compressed frames are reported, not decompressed.
class ProtobufPayloadDecoder implements PayloadDecoder {
  /// Creates a decoder. By default it handles protobuf and gRPC content
  /// types; pass [matches] to choose payloads yourself.
  const ProtobufPayloadDecoder({
    required Object? Function(Uint8List message, PayloadContext context) decode,
    bool Function(PayloadContext context)? matches,
  })  : _decode = decode,
        _matches = matches;

  final Object? Function(Uint8List message, PayloadContext context) _decode;
  final bool Function(PayloadContext context)? _matches;

  @override
  PayloadFormat get format => PayloadFormat.protobuf;

  @override
  bool canDecode(PayloadContext context) {
    final matches = _matches;
    if (matches != null) return matches(context);
    final type = context.contentType?.toLowerCase() ?? '';
    return type.contains('protobuf') ||
        (type.startsWith('application/grpc') && !type.contains('-text'));
  }

  @override
  Object? decode(Uint8List bytes, PayloadContext context) {
    final type = context.contentType?.toLowerCase() ?? '';
    if (!type.startsWith('application/grpc')) return _decode(bytes, context);

    final frames = parseGrpcFrames(bytes);
    if (frames == null) return null;
    final messages = [
      for (final frame in frames)
        if (!frame.isTrailer)
          frame.isCompressed
              ? '<compressed message, ${frame.data.length} bytes>'
              : _decode(frame.data, context),
    ];
    if (messages.isEmpty) return null;
    return messages.length == 1 ? messages.single : messages;
  }
}
