import 'package:dio/dio.dart';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/contracts/payload_decoder.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../core/entities/protocol_details.dart';
import '../../protocols/webhook/webhook_config.dart';
import '../../security/body_capture.dart';
import '../log_capture.dart';

/// Set `extra[netoscopeSkipKey] = true` on a Dio request to exclude it from
/// logging.
const String netoscopeSkipKey = 'netoscope.skip';

/// Set `extra[netoscopeWebhookKey]` to a [WebhookAttempt] to describe a
/// webhook delivery attempt.
const String netoscopeWebhookKey = 'netoscope.webhook';

/// A Dio [Interceptor] that records every call it sees.
///
/// It only observes: requests, responses and errors are always passed on
/// unchanged with `handler.next`, and response data is never read from
/// streams or modified.
class DioNetworkLogger extends Interceptor {
  /// Creates an interceptor recording through [capture].
  DioNetworkLogger(this._capture);

  final LogCapture _capture;

  /// Per-request timing, keyed weakly by the request so nothing is retained
  /// once Dio is done with it.
  final Expando<_Timing> _timings = Expando('netoscope.timing');

  /// Maps progress wrappers created here back to the app's callbacks, so a
  /// retried request is never wrapped twice.
  final Expando<ProgressCallback> _originals = Expando('netoscope.progress');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_capture.config.isEnabled) {
      final timing = _Timing(_capture.nextId());
      _timings[options] = timing;
      if (_capture.config.captureTransferProgress) {
        _observeProgress(options, timing);
      }
    }
    handler.next(options);
  }

  /// Wraps progress callbacks the app already set. The app's callback is
  /// always invoked first, with the same arguments; no callback is added
  /// where there was none.
  void _observeProgress(RequestOptions options, _Timing timing) {
    final send = options.onSendProgress;
    if (send != null) {
      final original = _originals[send] ?? send;
      void wrapper(int sent, int total) {
        original(sent, total);
        timing
          ..sent = sent
          ..sendTotal = total;
      }

      _originals[wrapper] = original;
      options.onSendProgress = wrapper;
    }
    final receive = options.onReceiveProgress;
    if (receive != null) {
      final original = _originals[receive] ?? receive;
      void wrapper(int received, int total) {
        original(received, total);
        timing
          ..received = received
          ..receiveTotal = total;
      }

      _originals[wrapper] = original;
      options.onReceiveProgress = wrapper;
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _record(response.requestOptions, response, null);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(err.requestOptions, err.response, err);
    handler.next(err);
  }

  void _record(
    RequestOptions options,
    Response<dynamic>? response,
    DioException? exception,
  ) {
    final timing = _timings[options];
    _timings[options] = null;
    _capture.record(() {
      if (options.extra[netoscopeSkipKey] == true) return null;
      final uri = options.uri;
      if (!_capture.shouldLog(uri)) return null;
      final responseHeaders = response?.headers.map;
      final rawRequestHeaders = _requestHeaders(options.headers);
      final error = exception == null ? null : _error(exception);
      final hint = options.extra[netoscopeWebhookKey];
      final requestData = options.data;
      final inspection = _capture.inspectHttp(
        method: options.method,
        url: uri,
        requestHeaders: rawRequestHeaders,
        requestContentType: options.contentType,
        requestPayload: requestData is FormData
            ? _graphQLMultipartOperations(requestData)
            : requestData,
        statusCode: response?.statusCode,
        responseContentType: response?.headers.value(Headers.contentTypeHeader),
        responseHeaders: {
          if (responseHeaders != null)
            for (final e in responseHeaders.entries) e.key: e.value.join(', '),
        },
        responsePayload: response?.data is ResponseBody ? null : response?.data,
        error: error,
        webhookAttempt: hint is WebhookAttempt ? hint : null,
      );
      return NetworkLogEntry(
        id: timing?.id ?? _capture.nextId(),
        method: options.method,
        url: _capture.url(uri),
        timestamp: timing?.startedAt ?? DateTime.now(),
        duration: timing?.stopwatch.elapsed,
        protocol: inspection.protocol,
        details: [...inspection.details, ...?timing?.transfers()],
        requestHeaders: _capture.headers(rawRequestHeaders),
        requestBody: _capture.requestBody(
          (b) => _requestBody(
            b,
            options,
            _capture.payload(
              uri,
              MessageDirection.outgoing,
              contentType: options.contentType,
            ),
          ),
        ),
        requestSize: _requestSize(options),
        statusCode: response?.statusCode,
        responseHeaders: responseHeaders == null
            ? const {}
            : _capture.headers({
                for (final e in responseHeaders.entries)
                  e.key: e.value.join(', '),
              }),
        responseBody: response == null
            ? null
            : _capture.responseBody(
                (b) => _responseBody(
                  b,
                  response,
                  _capture.payload(
                    uri,
                    MessageDirection.incoming,
                    contentType:
                        response.headers.value(Headers.contentTypeHeader),
                  ),
                ),
              ),
        responseSize: response == null ? null : _responseSize(response),
        error: inspection.error,
      );
    });
  }

  static Map<String, String> _requestHeaders(Map<String, dynamic> headers) => {
        for (final entry in headers.entries)
          if (entry.value != null)
            entry.key: entry.value is Iterable
                ? (entry.value as Iterable<Object?>).join(', ')
                : '${entry.value}',
      };

  /// The `operations` field of a GraphQL multipart upload, if present.
  static String? _graphQLMultipartOperations(FormData data) {
    for (final field in data.fields) {
      if (field.key == 'operations') return field.value;
    }
    return null;
  }

  static NetworkLogBody? _requestBody(
    BodyCapture bodies,
    RequestOptions o,
    PayloadContext context,
  ) {
    final data = o.data;
    if (data is FormData) {
      return bodies.multipart(
        contentType: o.contentType,
        fields: data.fields,
        files: [
          for (final file in data.files)
            MultipartFileInfo(
              field: file.key,
              filename: file.value.filename,
              contentType: file.value.contentType?.toString(),
              length: file.value.length,
            ),
        ],
      );
    }
    return bodies.capture(data, context: context);
  }

  static int? _requestSize(RequestOptions options) {
    final data = options.data;
    if (data is FormData) return data.length;
    return BodyCapture.sizeOf(data) ??
        _parseLength(options.headers[Headers.contentLengthHeader]);
  }

  static NetworkLogBody? _responseBody(
    BodyCapture bodies,
    Response<dynamic> r,
    PayloadContext context,
  ) {
    final data = r.data;
    // ResponseType.stream: the caller owns the stream; never listen to it.
    if (data is ResponseBody) return bodies.stream();
    return bodies.capture(data, context: context);
  }

  static int? _responseSize(Response<dynamic> response) =>
      _parseLength(response.headers.value(Headers.contentLengthHeader)) ??
      BodyCapture.sizeOf(response.data);

  static int? _parseLength(Object? value) =>
      value == null ? null : int.tryParse('$value');

  NetworkLogError _error(DioException exception) {
    final type = switch (exception.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        NetworkErrorType.timeout,
      DioExceptionType.badCertificate => NetworkErrorType.badCertificate,
      DioExceptionType.badResponse => NetworkErrorType.badResponse,
      DioExceptionType.cancel => NetworkErrorType.cancelled,
      DioExceptionType.connectionError => NetworkErrorType.connection,
      _ => NetworkErrorType.unknown,
    };
    final message =
        exception.message ?? exception.error?.toString() ?? exception.type.name;
    return _capture.error(type, message);
  }
}

class _Timing {
  _Timing(this.id)
      : startedAt = DateTime.now(),
        stopwatch = Stopwatch()..start();

  final String id;
  final DateTime startedAt;
  final Stopwatch stopwatch;
  int? sent;
  int? sendTotal;
  int? received;
  int? receiveTotal;

  List<TransferDetails> transfers() => [
        if (sent != null)
          TransferDetails(
            direction: TransferDirection.upload,
            bytesTransferred: sent!,
            totalBytes: (sendTotal ?? -1) > 0 ? sendTotal : null,
          ),
        if (received != null)
          TransferDetails(
            direction: TransferDirection.download,
            bytesTransferred: received!,
            totalBytes: (receiveTotal ?? -1) > 0 ? receiveTotal : null,
          ),
      ];
}
