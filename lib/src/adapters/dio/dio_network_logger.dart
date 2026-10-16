import 'package:dio/dio.dart';

import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../security/body_capture.dart';
import '../log_capture.dart';

/// Set `extra[netoscopeSkipKey] = true` on a Dio request to exclude it from
/// logging.
const String netoscopeSkipKey = 'netoscope.skip';

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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_capture.config.isEnabled) {
      _timings[options] = _Timing(_capture.nextId());
    }
    handler.next(options);
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
      return NetworkLogEntry(
        id: timing?.id ?? _capture.nextId(),
        method: options.method,
        url: _capture.url(uri),
        timestamp: timing?.startedAt ?? DateTime.now(),
        duration: timing?.stopwatch.elapsed,
        requestHeaders: _capture.headers(_requestHeaders(options.headers)),
        requestBody: _capture.requestBody((b) => _requestBody(b, options)),
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
            : _capture.responseBody((b) => _responseBody(b, response)),
        responseSize: response == null ? null : _responseSize(response),
        error: exception == null ? null : _error(exception),
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

  static NetworkLogBody? _requestBody(BodyCapture bodies, RequestOptions o) {
    final data = o.data;
    if (data is FormData) {
      return bodies.multipart(
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
    return bodies.capture(data, contentType: o.contentType);
  }

  static int? _requestSize(RequestOptions options) {
    final data = options.data;
    if (data is FormData) return data.length;
    return BodyCapture.sizeOf(data) ??
        _parseLength(options.headers[Headers.contentLengthHeader]);
  }

  static NetworkLogBody? _responseBody(
      BodyCapture bodies, Response<dynamic> r) {
    final data = r.data;
    // ResponseType.stream: the caller owns the stream; never listen to it.
    if (data is ResponseBody) return bodies.stream();
    return bodies.capture(
      data,
      contentType: r.headers.value(Headers.contentTypeHeader),
    );
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
}
