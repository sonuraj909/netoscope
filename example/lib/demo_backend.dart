import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An offline, deterministic stand-in for a real API so the example runs
/// without network access or credentials.
///
/// Replace `dio.httpClientAdapter = DemoBackendAdapter()` with your real
/// configuration to log genuine traffic.
class DemoBackendAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    switch (path) {
      case '/graphql':
        await _latency(const Duration(milliseconds: 150));
        return _json({
          'data': {
            'viewer': {'id': '1', 'name': 'Ada Lovelace', 'email': null},
          },
          'errors': [
            {
              'message': 'Not authorized to read email',
              'path': ['viewer', 'email'],
              'extensions': {'code': 'FORBIDDEN'},
            },
          ],
        });
      case '/hooks/orders':
        await _latency(const Duration(milliseconds: 200));
        return _json({'error': 'receiver unavailable'}, status: 503);
      case '/users':
        await _latency(const Duration(milliseconds: 180));
        return _json([
          {'id': 1, 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
          {'id': 2, 'name': 'Alan Turing', 'email': 'alan@example.com'},
        ]);
      case '/auth/login':
        await _latency(const Duration(milliseconds: 250));
        return _json({
          'access_token': 'eyJhbGciOiJIUzI1NiJ9.demo.signature',
          'refresh_token': 'demo-refresh-token',
          'user': {'id': 1, 'name': 'Ada Lovelace'},
        });
      case '/reports/annual':
        await _latency(const Duration(milliseconds: 2500));
        return _json({'year': 2026, 'revenue': 1250000});
      case '/flaky':
        await _latency(const Duration(milliseconds: 400));
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
          message: 'The demo server did not answer in time.',
        );
      case '/long-poll':
        // Never answers; used to demonstrate cancellation.
        await (cancelFuture ?? Completer<void>().future);
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled',
        );
      default:
        await _latency(const Duration(milliseconds: 90));
        return _json({'error': 'Not found', 'path': path}, status: 404);
    }
  }

  @override
  void close({bool force = false}) {}

  static Future<void> _latency(Duration duration) =>
      Future<void>.delayed(duration);

  static ResponseBody _json(Object body, {int status = 200}) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'set-cookie': ['session=demo-session; HttpOnly'],
        },
      );
}

/// An offline `package:http` client for the same demo backend, including a
/// Server-Sent Events endpoint at `/events`.
http.Client demoHttpClient() => MockClient.streaming((request, _) async {
      if (request.url.path == '/events') {
        return http.StreamedResponse(
          _priceEvents(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode(
                {'status': 'ok', 'region': 'eu-west', 'api_key': 'demo'}),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

Stream<List<int>> _priceEvents() async* {
  for (var i = 1; i <= 3; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    yield utf8.encode(
      'event: price\nid: $i\ndata: {"symbol":"NETO","price":${100 + i}}\n\n',
    );
  }
}

/// A simulated WebSocket that echoes every message back, standing in for a
/// `WebSocketChannel` (which has the same `stream`/`sink` shape).
class DemoEchoSocket {
  final _incoming = StreamController<String>();
  final _outgoing = StreamController<String>();

  /// The close code reported once the socket is closed.
  int? closeCode;

  /// Messages from the "server".
  Stream<String> get stream => _incoming.stream;

  /// Messages to the "server".
  StreamSink<String> get sink => _outgoing.sink;

  /// Starts echoing.
  DemoEchoSocket() {
    _outgoing.stream.listen((message) async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!_incoming.isClosed) _incoming.add('echo: $message');
    });
  }

  /// Closes both directions with a normal close code.
  Future<void> close() async {
    closeCode = 1000;
    await _outgoing.close();
    await _incoming.close();
  }
}
