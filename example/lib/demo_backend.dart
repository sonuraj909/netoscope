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

/// An offline `package:http` client for the same demo backend.
http.Client demoHttpClient() => MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return http.Response(
        jsonEncode({'status': 'ok', 'region': 'eu-west', 'api_key': 'demo'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
