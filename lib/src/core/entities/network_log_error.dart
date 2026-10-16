/// The category of a failed network call.
enum NetworkErrorType {
  /// Connecting, sending or receiving took longer than allowed.
  timeout,

  /// The connection could not be established or was dropped.
  connection,

  /// The server certificate was rejected.
  badCertificate,

  /// A response was received but the client treated its status as an error.
  badResponse,

  /// The client cancelled the call.
  cancelled,

  /// Any other failure.
  unknown,
}

/// An immutable description of why a network call failed.
class NetworkLogError {
  /// Creates an error description.
  const NetworkLogError({required this.type, required this.message});

  /// The failure category.
  final NetworkErrorType type;

  /// A human-readable, redacted message.
  final String message;

  /// A JSON-compatible representation of this error.
  Map<String, Object?> toJson() => {'type': type.name, 'message': message};

  @override
  bool operator ==(Object other) =>
      other is NetworkLogError &&
      other.type == type &&
      other.message == message;

  @override
  int get hashCode => Object.hash(type, message);

  @override
  String toString() => 'NetworkLogError(${type.name}: $message)';
}
