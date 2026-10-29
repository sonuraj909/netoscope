import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/entities/network_event_kind.dart';
import '../../core/entities/network_log_body.dart';
import '../../core/entities/network_log_entry.dart';
import '../../core/entities/network_log_error.dart';
import '../../protocols/grpc/grpc_web_inspector.dart';
import '../../security/body_capture.dart';
import '../../security/payload_format_detector.dart';
import '../../core/entities/payload_format.dart';
import '../log_capture.dart';
import '../observe_stream.dart';
import '../realtime/sse_recorder.dart';

/// Installed `dart:io` capture.
abstract interface class DartIoCapture {
  /// Stops wrapping new `HttpClient`s and restores the previous
  /// `HttpOverrides`, if this capture is still the global one. When other
  /// overrides were installed on top and still delegate to this one, it
  /// stays in their chain as a pass-through.
  void uninstall();
}

/// Wraps every `HttpClient` created from now on (directly, by `IOClient`,
/// Dio's default adapter, `Image.network`, SDKs, …) so its calls are
/// recorded. Calls already recorded by the Dio or `http` integrations are
/// skipped. Any previously installed `HttpOverrides` keeps working.
DartIoCapture? installDartIoCapture(LogCapture capture) {
  final overrides = _NetoscopeHttpOverrides(capture, HttpOverrides.current);
  HttpOverrides.global = overrides;
  return overrides;
}

class _NetoscopeHttpOverrides extends HttpOverrides implements DartIoCapture {
  _NetoscopeHttpOverrides(this._capture, this._previous);

  final LogCapture _capture;
  final HttpOverrides? _previous;
  bool _installed = true;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner =
        _previous?.createHttpClient(context) ?? super.createHttpClient(context);
    return _installed ? _LoggingHttpClient(inner, _capture) : inner;
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      _previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);

  @override
  void uninstall() {
    _installed = false;
    if (identical(HttpOverrides.current, this)) {
      HttpOverrides.global = _previous;
    }
  }
}

/// Forwards everything to [_inner], wrapping opened requests.
class _LoggingHttpClient implements HttpClient {
  _LoggingHttpClient(this._inner, this._capture);

  final HttpClient _inner;
  final LogCapture _capture;

  Future<HttpClientRequest> _open(
    String method,
    Uri url,
    Future<HttpClientRequest> Function() open,
  ) {
    if (!_capture.shouldLog(url) || _capture.isClaimed(method, url)) {
      return open();
    }
    final call = _Call(_capture.nextId(), method, url, _capture.currentTags());
    return open().then<HttpClientRequest>(
      (request) => _LoggingRequest(request, _capture, call),
      onError: (Object error, StackTrace stackTrace) {
        _record(_capture, call, error: error);
        return Future<HttpClientRequest>.error(error, stackTrace);
      },
    );
  }

  static Uri _uri(String host, int port, String path) {
    final query = path.indexOf('?');
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: query < 0 ? path : path.substring(0, query),
      query: query < 0 ? null : path.substring(query + 1),
    );
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _open(
        method,
        _uri(host, port, path),
        () => _inner.open(method, host, port, path),
      );

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _open(method, url, () => _inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
        f,
  ) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) =>
      _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )? f,
  ) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  void close({bool force = false}) => _inner.close(force: force);
}

class _Call {
  _Call(this.id, this.method, this.url, this.tags)
      : startedAt = DateTime.now(),
        stopwatch = Stopwatch()..start();

  final String id;
  final String method;
  final Uri url;
  final List<String> tags;
  final DateTime startedAt;
  final Stopwatch stopwatch;
  Map<String, String> requestHeaders = const {};
  final BytesBuilder requestBytes = BytesBuilder();
  int requestSize = 0;
  bool requestStreamed = false;
}

/// Forwards everything to [_inner], copying written body bytes (up to the
/// parse limit) and wrapping the response.
class _LoggingRequest implements HttpClientRequest {
  _LoggingRequest(this._inner, this._capture, this._call);

  final HttpClientRequest _inner;
  final LogCapture _capture;
  final _Call _call;
  Future<HttpClientResponse>? _response;

  void _copy(List<int> bytes) {
    _call.requestSize += bytes.length;
    final room = BodyCapture.parseLimit - _call.requestBytes.length;
    if (room > 0) {
      _call.requestBytes
          .add(bytes.length <= room ? bytes : bytes.sublist(0, room));
    }
  }

  void _copyText(Object? object) {
    try {
      _copy(encoding.encode('$object'));
    } catch (_) {
      // Unencodable text is still sent by the inner request.
    }
  }

  Future<HttpClientResponse> _wrapped() => _response ??= _inner.done.then(
        (response) => _wrapResponse(response, _capture, _call),
        onError: (Object error, StackTrace stackTrace) {
          _record(_capture, _call, error: error);
          return Future<HttpClientResponse>.error(error, stackTrace);
        },
      );

  @override
  Future<HttpClientResponse> close() {
    _call.requestHeaders = _headers(_inner.headers);
    final response = _wrapped();
    unawaited(_inner.close().then((_) {}, onError: (Object _) {}));
    return response;
  }

  @override
  Future<HttpClientResponse> get done => _wrapped();

  @override
  void add(List<int> data) {
    _copy(data);
    _inner.add(data);
  }

  @override
  void write(Object? object) {
    _copyText(object);
    _inner.write(object);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _copyText(objects.join(separator));
    _inner.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    _copyText(String.fromCharCode(charCode));
    _inner.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    _copyText('$object\n');
    _inner.writeln(object);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _call.requestStreamed = true;
    return _inner.addStream(stream.map((chunk) {
      _copy(chunk);
      return chunk;
    }));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> flush() => _inner.flush();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _inner.abort(exception, stackTrace);

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  bool get bufferOutput => _inner.bufferOutput;

  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  int get contentLength => _inner.contentLength;

  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  bool get followRedirects => _inner.followRedirects;

  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;

  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;
}

Map<String, String> _headers(HttpHeaders headers) {
  final result = <String, String>{};
  headers.forEach((name, values) => result[name] = values.join(', '));
  return result;
}

bool _isEventStream(HttpClientResponse response) =>
    response.statusCode >= 200 &&
    response.statusCode < 300 &&
    (response.headers.contentType?.mimeType.toLowerCase() ==
        'text/event-stream');

HttpClientResponse _wrapResponse(
  HttpClientResponse response,
  LogCapture capture,
  _Call call,
) {
  if (_isEventStream(response)) {
    final events = SseRecorder(
      capture,
      url: call.url,
      requestHeaders: call.requestHeaders,
    )..connected(
        statusCode: response.statusCode,
        responseHeaders: _headers(response.headers),
      );
    return _LoggingResponse(response, events.observeBytes(response));
  }

  final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
  final format = PayloadFormatDetector.fromContentType(contentType);
  // Large media (images, video, archives) is counted, not buffered.
  final textual = format == null ||
      (format != PayloadFormat.binary && format != PayloadFormat.multipart);
  final buffer = textual &&
          ((capture.config.captureResponseBody &&
                  capture.config.maxBodySize > 0) ||
              capture.config.detectGraphQL ||
              GrpcWebInspector.isGrpc(contentType))
      ? BytesBuilder()
      : null;
  var received = 0;
  var finished = false;

  void finish({Object? error, bool complete = true}) {
    if (finished) return;
    finished = true;
    _record(
      capture,
      call,
      response: response,
      error: error,
      responseBytes: buffer?.takeBytes(),
      responseComplete: complete && received <= BodyCapture.parseLimit,
      responseSize: complete ? received : null,
    );
  }

  final stream = observeStream<List<int>>(
    response,
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
  return _LoggingResponse(response, stream);
}

/// Forwards everything to [_inner]; the body is read through [_body].
class _LoggingResponse extends Stream<List<int>> implements HttpClientResponse {
  _LoggingResponse(this._inner, this._body);

  final HttpClientResponse _inner;
  final Stream<List<int>> _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _body.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  X509Certificate? get certificate => _inner.certificate;

  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  int get contentLength => _inner.contentLength;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  Future<Socket> detachSocket() => _inner.detachSocket();

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  bool get isRedirect => _inner.isRedirect;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  String get reasonPhrase => _inner.reasonPhrase;

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) =>
      _inner.redirect(method, url, followLoops);

  @override
  List<RedirectInfo> get redirects => _inner.redirects;

  @override
  int get statusCode => _inner.statusCode;
}

void _record(
  LogCapture capture,
  _Call call, {
  HttpClientResponse? response,
  Object? error,
  Uint8List? responseBytes,
  bool responseComplete = true,
  int? responseSize,
}) {
  final duration = call.stopwatch.elapsed;
  capture.record(() {
    final requestType = call.requestHeaders[HttpHeaders.contentTypeHeader];
    final responseHeaders = response == null
        ? const <String, String>{}
        : _headers(response.headers);
    final responseType = responseHeaders[HttpHeaders.contentTypeHeader];
    final requestBytes = call.requestBytes.toBytes();
    final requestComplete =
        !call.requestStreamed || call.requestSize <= BodyCapture.parseLimit;
    final inspection = capture.inspectHttp(
      method: call.method,
      url: call.url,
      requestHeaders: call.requestHeaders,
      requestContentType: requestType,
      requestPayload: requestBytes,
      statusCode: response?.statusCode,
      responseContentType: responseType,
      responseHeaders: responseHeaders,
      responsePayload: responseComplete ? responseBytes : null,
      error: error == null ? null : _error(capture, error),
    );
    return NetworkLogEntry(
      id: call.id,
      method: call.method,
      url: capture.url(call.url),
      timestamp: call.startedAt,
      duration: duration,
      protocol: inspection.protocol,
      details: inspection.details,
      tags: call.tags,
      requestHeaders: capture.headers(call.requestHeaders),
      requestBody: requestBytes.isEmpty
          ? null
          : capture.requestBody(
              (b) => b.fromBytes(
                requestBytes,
                isComplete: requestComplete &&
                    call.requestSize <= BodyCapture.parseLimit,
                context: capture.payload(
                  call.url,
                  MessageDirection.outgoing,
                  contentType: requestType,
                ),
              ),
            ),
      requestSize: call.requestSize == 0 ? null : call.requestSize,
      statusCode: response?.statusCode,
      responseHeaders: capture.headers(responseHeaders),
      responseBody: responseBytes == null
          ? _binaryPlaceholder(capture, responseType, responseSize)
          : capture.responseBody(
              (b) => b.fromBytes(
                responseBytes,
                isComplete: responseComplete,
                context: capture.payload(
                  call.url,
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

NetworkLogBody? _binaryPlaceholder(
  LogCapture capture,
  String? contentType,
  int? size,
) {
  if (size == null || size == 0 || !capture.config.captureResponseBody) {
    return null;
  }
  return NetworkLogBody(
    kind: NetworkBodyKind.binary,
    content: '<binary, $size bytes>',
    contentType: contentType,
  );
}

NetworkLogError _error(LogCapture capture, Object error) {
  final type = switch (error) {
    TimeoutException() => NetworkErrorType.timeout,
    HandshakeException() ||
    CertificateException() =>
      NetworkErrorType.badCertificate,
    SocketException() || HttpException() => NetworkErrorType.connection,
    _ => NetworkErrorType.unknown,
  };
  return capture.error(type, error.toString());
}
