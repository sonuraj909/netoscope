import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../security/body_capture.dart';
import '../log_capture.dart';

/// A `package:http` client that records every call made through it and
/// delegates the actual work to an inner client.
///
/// The response body is observed as the caller reads it, so nothing is
/// consumed on the caller's behalf. A call is recorded once its response
/// stream completes, fails or is cancelled by the caller.
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

    final call = _PendingCall(
      id: _capture.nextId(),
      request: request,
      requestBody: _capture.requestBody((b) => _requestBody(b, request)),
    );

    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } catch (error) {
      _record(call, error: error);
      rethrow;
    }
    return _observe(response, call);
  }

  @override
  void close() => _inner.close();

  http.StreamedResponse _observe(
    http.StreamedResponse response,
    _PendingCall call,
  ) {
    final buffer =
        _capture.config.captureResponseBody && _capture.config.maxBodySize > 0
            ? BytesBuilder()
            : null;
    var received = 0;
    var finished = false;
    StreamSubscription<List<int>>? subscription;

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

    final controller = StreamController<List<int>>(sync: true);
    controller
      ..onListen = () {
        subscription = response.stream.listen(
          (chunk) {
            received += chunk.length;
            if (buffer != null && buffer.length < BodyCapture.parseLimit) {
              final room = BodyCapture.parseLimit - buffer.length;
              buffer.add(chunk.length <= room ? chunk : chunk.sublist(0, room));
            }
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stackTrace) {
            finish(error: error, complete: false);
            controller.addError(error, stackTrace);
          },
          onDone: () {
            finish();
            controller.close();
          },
        );
      }
      ..onPause = () {
        subscription?.pause();
      }
      ..onResume = () {
        subscription?.resume();
      }
      ..onCancel = () {
        finish(complete: false);
        return subscription?.cancel();
      };

    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

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
      return NetworkLogEntry(
        id: call.id,
        method: request.method,
        url: _capture.url(request.url),
        timestamp: call.startedAt,
        duration: duration,
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
                  contentType: response?.headers['content-type'],
                  isComplete: responseComplete,
                ),
              ),
        responseSize: responseSize,
        error: error == null ? null : _error(error),
      );
    });
  }

  static NetworkLogBody? _requestBody(
    BodyCapture bodies,
    http.BaseRequest request,
  ) {
    if (request is http.Request) {
      return bodies.fromBytes(
        request.bodyBytes,
        contentType: request.headers['content-type'],
      );
    }
    if (request is http.MultipartRequest) {
      return bodies.multipart(
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
    required this.requestBody,
  })  : startedAt = DateTime.now(),
        stopwatch = Stopwatch()..start();

  final String id;
  final http.BaseRequest request;
  final NetworkLogBody? requestBody;
  final DateTime startedAt;
  final Stopwatch stopwatch;
}
