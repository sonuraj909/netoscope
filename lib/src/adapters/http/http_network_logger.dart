import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/contracts/payload_decoder.dart';
import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../protocols/grpc/grpc_web_inspector.dart';
import '../../security/body_capture.dart';
import '../log_capture.dart';
import '../observe_stream.dart';
import '../realtime/sse_recorder.dart';

/// A `package:http` client that records every call made through it and
/// delegates the actual work to an inner client.
///
/// The response body is observed as the caller reads it, so nothing is
/// consumed on the caller's behalf. A call is recorded once its response
/// stream completes, fails or is cancelled by the caller.
///
/// Successful `text/event-stream` responses are recorded as a Server-Sent
/// Events connection: an opened event when headers arrive, one entry per
/// event as the caller reads them, and a close when the stream ends. Their
/// bodies are not buffered.
///
/// Limitations: the returned [http.StreamedResponse] is a plain
/// `StreamedResponse`, so client-specific subclasses (such as
/// `IOStreamedResponse`) are not preserved. [http.StreamedRequest] bodies are
/// not captured, because reading them would consume the stream.
class HttpNetworkLogger extends http.BaseClient {
  /// Wraps [inner], recording through [capture].
  HttpNetworkLogger(this._inner, this._capture);

  final http.Client _inner;
  final LogCapture _capture;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_capture.shouldLog(request.url)) return _inner.send(request);

    final contentType = request.headers['content-type'];
    final payload = _requestPayload(request);
    final call = _PendingCall(
      id: _capture.nextId(),
      request: request,
      requestPayload: payload,
      requestBody: _capture.requestBody(
        (b) => _requestBody(
          b,
          request,
          _capture.payload(
            request.url,
            MessageDirection.outgoing,
            contentType: contentType,
          ),
        ),
      ),
      tags: _capture.currentTags(),
      mayNeedResponseBytes: GrpcWebInspector.isGrpc(contentType) ||
          (_capture.config.detectGraphQL &&
              _capture.graphQL.inspectHttp(
                    method: request.method,
                    url: request.url,
                    requestContentType: contentType,
                    requestBody: payload,
                  ) !=
                  null),
    );

    final http.StreamedResponse response;
    // Claim the call while the inner client opens it, so dart:io capture
    // (if enabled) does not record it a second time.
    _capture.claim(request.method, request.url);
    try {
      response = await _inner.send(request);
    } catch (error) {
      _record(call, error: error);
      rethrow;
    } finally {
      _capture.release(request.method, request.url);
    }
    if (_isEventStream(response)) return _observeEvents(response, call);
    return _observe(response, call);
  }

  @override
  void close() => _inner.close();

  static bool _isEventStream(http.StreamedResponse response) =>
      response.statusCode >= 200 &&
      response.statusCode < 300 &&
      (response.headers['content-type']
              ?.toLowerCase()
              .startsWith('text/event-stream') ??
          false);

  http.StreamedResponse _observeEvents(
    http.StreamedResponse response,
    _PendingCall call,
  ) {
    final events = SseRecorder(
      _capture,
      url: call.request.url,
      requestHeaders: call.request.headers,
    )..connected(
        statusCode: response.statusCode,
        responseHeaders: response.headers,
      );
    return _copy(response, events.observeBytes(response.stream));
  }

  http.StreamedResponse _observe(
    http.StreamedResponse response,
    _PendingCall call,
  ) {
    final config = _capture.config;
    final buffer = (config.captureResponseBody && config.maxBodySize > 0) ||
            call.mayNeedResponseBytes ||
            GrpcWebInspector.isGrpc(response.headers['content-type'])
        ? BytesBuilder()
        : null;
    var received = 0;
    var finished = false;

    void finish({Object? error, bool complete = true}) {
      if (finished) return;
      finished = true;
      _record(
        call,
        response: response,
        error: error,
        responseBytes: buffer?.takeBytes(),
        responseComplete: complete && received <= BodyCapture.parseLimit,
        responseSize: complete ? received : response.contentLength,
      );
    }

    final stream = observeStream<List<int>>(
      response.stream,
      onData: (chunk) {
        received += chunk.length;
        if (buffer != null && buffer.length < BodyCapture.parseLimit) {
          final room = BodyCapture.parseLimit - buffer.length;
          buffer.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
        }
      },
      onError: (error) => finish(error: error, complete: false),
      onDone: finish,
      onCancel: () => finish(complete: false),
    );
    return _copy(response, stream);
  }

  static http.StreamedResponse _copy(
    http.StreamedResponse response,
    Stream<List<int>> stream,
  ) =>
      http.StreamedResponse(
        stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );

  void _record(
    _PendingCall call, {
    http.StreamedResponse? response,
    Object? error,
    Uint8List? responseBytes,
    bool responseComplete = true,
    int? responseSize,
  }) {
    final duration = call.stopwatch.elapsed;
    _capture.record(() {
      final request = call.request;
      final responseType = response?.headers['content-type'];
      final inspection = _capture.inspectHttp(
        method: request.method,
        url: request.url,
        requestHeaders: request.headers,
        requestContentType: request.headers['content-type'],
        requestPayload: call.requestPayload,
        statusCode: response?.statusCode,
        responseContentType: responseType,
        responseHeaders: response?.headers ?? const {},
        responsePayload: responseComplete ? responseBytes : null,
        error: error == null ? null : _error(error),
      );
      return NetworkLogEntry(
        id: call.id,
        method: request.method,
        url: _capture.url(request.url),
        timestamp: call.startedAt,
        duration: duration,
        protocol: inspection.protocol,
        details: inspection.details,
        tags: call.tags,
        requestHeaders: _capture.headers(request.headers),
        requestBody: call.requestBody,
        requestSize: request.contentLength,
        statusCode: response?.statusCode,
        responseHeaders:
            response == null ? const {} : _capture.headers(response.headers),
        responseBody: responseBytes == null
            ? null
            : _capture.responseBody(
                (b) => b.fromBytes(
                  responseBytes,
                  isComplete: responseComplete,
                  context: _capture.payload(
                    request.url,
                    MessageDirection.incoming,
                    contentType: responseType,
                  ),
                ),
              ),
        responseSize: responseSize,
        error: inspection.error,
      );
    });
  }

  /// The raw request payload used for protocol recognition: the body of an
  /// [http.Request], or the `operations` field of a GraphQL multipart upload.
  static Object? _requestPayload(http.BaseRequest request) {
    if (request is http.Request) return request.bodyBytes;
    if (request is http.MultipartRequest) return request.fields['operations'];
    return null;
  }

  static NetworkLogBody? _requestBody(
    BodyCapture bodies,
    http.BaseRequest request,
    PayloadContext context,
  ) {
    if (request is http.Request) {
      return bodies.fromBytes(request.bodyBytes, context: context);
    }
    if (request is http.MultipartRequest) {
      return bodies.multipart(
        contentType: request.headers['content-type'],
        fields: request.fields.entries,
        files: [
          for (final file in request.files)
            MultipartFileInfo(
              field: file.field,
              filename: file.filename,
              contentType: file.contentType.toString(),
              length: file.length,
            ),
        ],
      );
    }
    return request.contentLength == 0 ? null : bodies.stream();
  }

  NetworkLogError _error(Object error) {
    final type = switch (error) {
      http.RequestAbortedException() => NetworkErrorType.cancelled,
      TimeoutException() => NetworkErrorType.timeout,
      http.ClientException() => NetworkErrorType.connection,
      _ when _looksLikeCertificateError(error) =>
        NetworkErrorType.badCertificate,
      _ => NetworkErrorType.unknown,
    };
    return _capture.error(type, error.toString());
  }

  // Matches dart:io's HandshakeException/CertificateException without
  // importing dart:io, which would break web support.
  static bool _looksLikeCertificateError(Object error) {
    final name = error.runtimeType.toString();
    return name.contains('Handshake') || name.contains('Certificate');
  }
}

class _PendingCall {
  _PendingCall({
    required this.id,
    required this.request,
    required this.requestPayload,
    required this.requestBody,
    required this.mayNeedResponseBytes,
    required this.tags,
  })  : startedAt = DateTime.now(),
        stopwatch = Stopwatch()..start();

  final String id;
  final http.BaseRequest request;
  final Object? requestPayload;
  final NetworkLogBody? requestBody;
  final bool mayNeedResponseBytes;
  final List<String> tags;
  final DateTime startedAt;
  final Stopwatch stopwatch;
}
