import '../../core/entities/network_log_error.dart';
import '../../core/entities/protocol_details.dart';
import '../../security/log_redactor.dart';
import 'grpc_frames.dart';

/// Recognizes gRPC-Web calls made through an instrumented HTTP client.
///
/// Native gRPC uses HTTP/2 trailers that `package:http` and Dio do not
/// expose, so only gRPC-Web (binary `application/grpc-web…`) is supported
/// here. `application/grpc-web-text` (base64) bodies are identified but not
/// unframed.
class GrpcWebInspector {
  /// Creates an inspector.
  const GrpcWebInspector(this._redactor);

  final LogRedactor _redactor;

  /// Whether [contentType] denotes a gRPC or gRPC-Web payload.
  static bool isGrpc(String? contentType) =>
      contentType?.toLowerCase().trimLeft().startsWith('application/grpc') ??
      false;

  /// Inspects an exchange, or returns `null` if it is not gRPC.
  GrpcDetails? inspect({
    required Uri url,
    String? requestContentType,
    String? responseContentType,
    Map<String, String> responseHeaders = const {},
    List<int>? requestBytes,
    List<int>? responseBytes,
  }) {
    if (!isGrpc(requestContentType) && !isGrpc(responseContentType)) {
      return null;
    }
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final service = segments.length >= 2 ? segments[segments.length - 2] : '';
    final method = segments.isEmpty ? '' : segments.last;

    final requestFrames =
        requestBytes == null ? null : parseGrpcFrames(requestBytes);
    final responseFrames =
        responseBytes == null ? null : parseGrpcFrames(responseBytes);
    final headers = {
      for (final e in responseHeaders.entries) e.key.toLowerCase(): e.value,
    };
    final trailers = <String, String>{
      ...headers,
      if (responseFrames != null)
        for (final frame in responseFrames)
          if (frame.isTrailer) ...parseGrpcTrailers(frame.data),
    };
    final status = int.tryParse(trailers['grpc-status'] ?? '');
    final rawMessage = trailers['grpc-message'];
    String? message;
    if (rawMessage != null) {
      try {
        message = Uri.decodeComponent(rawMessage);
      } on ArgumentError {
        message = rawMessage;
      }
      message = _redactor.redactText(message);
    }
    final type = '${requestContentType ?? responseContentType}'.toLowerCase();
    return GrpcDetails(
      service: service,
      method: method,
      statusCode: status,
      statusMessage: message,
      messagesSent: requestFrames?.where((f) => !f.isTrailer).length,
      messagesReceived: responseFrames?.where((f) => !f.isTrailer).length,
      isWeb: type.contains('grpc-web'),
    );
  }

  /// An error for a non-OK gRPC status, or `null` when the status is OK or
  /// unknown.
  static NetworkLogError? errorFor(GrpcDetails details) {
    final code = details.statusCode;
    if (code == null || code == 0) return null;
    final type = switch (code) {
      1 => NetworkErrorType.cancelled,
      4 => NetworkErrorType.timeout,
      14 => NetworkErrorType.connection,
      _ => NetworkErrorType.unknown,
    };
    final message = details.statusMessage;
    return NetworkLogError(
      type: type,
      message: message == null || message.isEmpty
          ? 'gRPC ${details.statusName}'
          : 'gRPC ${details.statusName}: $message',
    );
  }
}
