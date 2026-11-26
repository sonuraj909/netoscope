import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

const _marker = 'LEAK';

/// Holds every response until the test releases it.
class _GatedBackend implements HttpClientAdapter {
  final List<Completer<void>> gates = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await requestStream?.drain<void>();
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return ResponseBody.fromString(
      jsonEncode({'access_token': 'LEAK-response', 'n': gates.length}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  void releaseAll() {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('pending calls, replays and comparisons contain no secrets', () async {
    final netoscope = Netoscope(
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        enableReplay: true,
      ),
    );
    addTearDown(netoscope.dispose);
    final backend = _GatedBackend();
    final dio = netoscope.attachDio(Dio()..httpClientAdapter = backend);

    Future<Object?> call() => dio.post<Object?>(
          'https://bob:LEAK-userinfo@api.dev/login#access_token=LEAK-fragment',
          queryParameters: {'api_key': 'LEAK-query', 'page': '1'},
          data: {'password': 'LEAK-password', 'user': 'ada'},
          options: Options(headers: {'Authorization': 'Bearer LEAK-bearer'}),
        );

    final first = call();
    await pumpEventQueue();
    for (final pending in netoscope.pendingCalls) {
      expect('$pending ${pending.url}', isNot(contains(_marker)));
    }
    backend.releaseAll();
    await first;

    final replay = netoscope.replay(netoscope.logs.single);
    await pumpEventQueue();
    expect(netoscope.pendingCalls, hasLength(1));
    expect('${netoscope.pendingCalls.single.url}', isNot(contains(_marker)));
    backend.releaseAll();
    await replay;

    expect(netoscope.logs, hasLength(2));
    for (final entry in netoscope.logs) {
      expect(jsonEncode(entry.toJson()), isNot(contains(_marker)));
    }

    final comparison = NetworkLogComparison(
      netoscope.logs.last,
      netoscope.logs.first,
    );
    final text = [
      ...comparison.summary,
      ...comparison.queryParameters,
      ...comparison.requestHeaders,
      ...comparison.responseHeaders,
      ...comparison.requestBody,
      ...comparison.responseBody,
    ].join('\n');
    expect(text, isNot(contains(_marker)));
    expect(netoscope.exportHar(), isNot(contains(_marker)));
  });
}
