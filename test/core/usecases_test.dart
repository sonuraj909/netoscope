import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/core/usecases/clear_network_logs.dart';
import 'package:netoscope/src/core/usecases/get_network_logs.dart';
import 'package:netoscope/src/core/usecases/record_network_log.dart';

import '../support/fixtures.dart';

class _ThrowingSink implements NetworkLogSink {
  @override
  void write(NetworkLogEntry entry) => throw StateError('sink failure');
}

void main() {
  test('RecordNetworkLog stores the entry and forwards it to sinks', () {
    final store = InMemoryNetworkLogStore();
    final sink = RecordingSink();
    final entry = makeEntry();

    RecordNetworkLog(store, sinks: [sink])(entry);

    expect(store.entries, [entry]);
    expect(sink.received, [entry]);
  });

  test('a failing sink does not stop storage or later sinks', () {
    final store = InMemoryNetworkLogStore();
    final sink = RecordingSink();

    RecordNetworkLog(store, sinks: [_ThrowingSink(), sink])(makeEntry());

    expect(store.entries, hasLength(1));
    expect(sink.received, hasLength(1));
  });

  test('GetNetworkLogs and ClearNetworkLogs delegate to the store', () async {
    final store = InMemoryNetworkLogStore();
    final get = GetNetworkLogs(store);
    final changes = <List<NetworkLogEntry>>[];
    final subscription = get.watch().listen(changes.add);

    store.add(makeEntry());
    expect(get(), hasLength(1));

    ClearNetworkLogs(store)();
    expect(get(), isEmpty);

    await pumpEventQueue();
    expect(changes.map((c) => c.length), [1, 0]);
    await subscription.cancel();
  });
}
