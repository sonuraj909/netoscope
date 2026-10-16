import 'dart:typed_data';

/// One length-prefixed gRPC message frame.
class GrpcFrame {
  /// Creates a frame.
  const GrpcFrame({
    required this.data,
    required this.isCompressed,
    required this.isTrailer,
  });

  /// The frame payload.
  final Uint8List data;

  /// Whether the payload is compressed (flag bit 0).
  final bool isCompressed;

  /// Whether this is a gRPC-Web trailer frame (flag bit 7).
  final bool isTrailer;
}

/// Splits a gRPC or gRPC-Web body into frames.
///
/// Each frame is a 1-byte flag, a 4-byte big-endian length and the payload.
/// Returns `null` when [bytes] is not well-formed (for example truncated).
List<GrpcFrame>? parseGrpcFrames(List<int> bytes) {
  final frames = <GrpcFrame>[];
  var offset = 0;
  while (offset < bytes.length) {
    if (bytes.length - offset < 5) return null;
    final flag = bytes[offset];
    final length = (bytes[offset + 1] << 24) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 8) |
        bytes[offset + 4];
    final start = offset + 5;
    final end = start + length;
    if (length < 0 || end > bytes.length) return null;
    frames.add(
      GrpcFrame(
        data: Uint8List.fromList(bytes.sublist(start, end)),
        isCompressed: flag & 0x01 != 0,
        isTrailer: flag & 0x80 != 0,
      ),
    );
    offset = end;
  }
  return frames;
}

/// Parses a gRPC-Web trailer frame (`name: value` lines) into a map with
/// lower-case keys.
Map<String, String> parseGrpcTrailers(List<int> data) {
  final text = String.fromCharCodes(data);
  return {
    for (final line in text.split(RegExp(r'\r?\n')))
      if (line.contains(':'))
        line.substring(0, line.indexOf(':')).trim().toLowerCase():
            line.substring(line.indexOf(':') + 1).trim(),
  };
}
