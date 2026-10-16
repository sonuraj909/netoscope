import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import 'support/fixtures.dart';

void main() {
  const quiet = NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none);

  test('exposes history, clearing and export over one store', () async {
    final store = InMemoryNetworkLogStore();
    final netoscope = Netoscope(config: quiet, store: store);
    final changes = <int>[];
    final sub = netoscope.logChanges.listen((e) => changes.add(e.length));

    store.add(makeEntry(id: 'a'));
    expect(netoscope.logs.single.id, 'a');
    expect((jsonDecode(netoscope.exportJson()) as Map)['count'], 1);

    netoscope.clearLogs();
    expect(netoscope.logs, isEmpty);
    await pumpEventQueue();
    expect(changes, [1, 0]);

    await sub.cancel();
    await netoscope.dispose();
  });

  test('history size follows the config', () {
    final netoscope = Netoscope(
      config: const NetworkLoggerConfig(
        consoleLogLevel: ConsoleLogLevel.none,
        maxHistorySize: 2,
      ),
    );
    final dio = Dio()
      ..httpClientAdapter = _OkAdapter()
      ..interceptors.add(netoscope.dioInterceptor);

    return Future.wait([
      for (var i = 0; i < 5; i++) dio.get<void>('https://a.dev/$i'),
    ]).then((_) => expect(netoscope.logs, hasLength(2)));
  });

  test('custom sinks receive every recorded entry', () async {
    final sink = RecordingSink();
    final netoscope = Netoscope(config: quiet, sinks: [sink]);
    final dio = Dio()
      ..httpClientAdapter = _OkAdapter()
      ..interceptors.add(netoscope.dioInterceptor);

    await dio.get<void>('https://a.dev/x');

    expect(sink.received, hasLength(1));
    expect(sink.received.single, same(netoscope.logs.single));
  });

  test('a disabled logger records nothing and hides the inspector', () {
    final netoscope =
        Netoscope(config: const NetworkLoggerConfig(enabled: false));
    expect(netoscope.isEnabled, isFalse);
    expect(netoscope.isInspectorAvailable, isFalse);
    expect(netoscope.dioInterceptor.runtimeType, Interceptor);
  });

  test('the Dio interceptor is created once', () {
    final netoscope = Netoscope(config: quiet);
    expect(netoscope.dioInterceptor, same(netoscope.dioInterceptor));
  });
}

class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString('ok', 200);

  @override
  void close({bool force = false}) {}
}
