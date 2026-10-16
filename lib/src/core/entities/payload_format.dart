/// The detected or decoded format of a captured payload.
///
/// Unlike an enum, formats are open: decoders can introduce their own, for
/// example `PayloadFormat('msgpack', label: 'MessagePack')`. Formats compare
/// equal by [id].
class PayloadFormat {
  /// Creates a format with a stable [id] and a display [label].
  const PayloadFormat(this.id, {required this.label});

  /// A stable identifier, such as `json`.
  final String id;

  /// A short display name, such as `JSON`.
  final String label;

  /// JSON documents.
  static const PayloadFormat json = PayloadFormat('json', label: 'JSON');

  /// XML documents.
  static const PayloadFormat xml = PayloadFormat('xml', label: 'XML');

  /// HTML documents.
  static const PayloadFormat html = PayloadFormat('html', label: 'HTML');

  /// Plain text.
  static const PayloadFormat text = PayloadFormat('text', label: 'Text');

  /// `application/x-www-form-urlencoded` bodies.
  static const PayloadFormat form = PayloadFormat('form', label: 'Form');

  /// Multipart forms.
  static const PayloadFormat multipart =
      PayloadFormat('multipart', label: 'Multipart');

  /// Protocol Buffers (decoded only when a decoder is registered).
  static const PayloadFormat protobuf =
      PayloadFormat('protobuf', label: 'Protobuf');

  /// Binary data of an unknown or non-textual format.
  static const PayloadFormat binary = PayloadFormat('binary', label: 'Binary');

  /// A stream that was not read.
  static const PayloadFormat stream = PayloadFormat('stream', label: 'Stream');

  /// An object that could not be serialized.
  static const PayloadFormat unsupported =
      PayloadFormat('unsupported', label: 'Unsupported');

  /// The built-in formats, in display order.
  static const List<PayloadFormat> builtIn = [
    json,
    xml,
    html,
    text,
    form,
    multipart,
    protobuf,
    binary,
    stream,
    unsupported,
  ];

  @override
  bool operator ==(Object other) => other is PayloadFormat && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PayloadFormat($id)';
}
