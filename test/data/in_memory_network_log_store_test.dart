import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import '../support/fixtures.dart';

void main() {
  group('InMemoryNetworkLogStore', () {
    test('orders entries newest first', () {
      final store = InMemoryNetworkLogStore()
        ..add(makeEntry(id: 'a'))
        ..add(makeEntry(id: 'b'))
        ..add(makeEntry(id: 'c'));

      expect(store.entries.map((e) => e.id), ['c', 'b', 'a']);
    });

    test('evicts the oldest entries beyond maxEntries', () {
      final store = InMemoryNetworkLogStore(maxEntries: 3);
      for (var i = 0; i < 10; i++) {
        store.add(makeEntry(id: '$i'));
      }
      expect(store.entries.map((e) => e.id), ['9', '8', '7']);
    });

    test('returns unmodifiable snapshots that do not change later', () {
      final store = InMemoryNetworkLogStore()..add(makeEntry(id: 'a'));
      final snapshot = store.entries;
      store.add(makeEntry(id: 'b'));

      expect(snapshot.map((e) => e.id), ['a']);
      expect(() => snapshot.add(makeEntry()), throwsUnsupportedError);
    });

    test('emits a snapshot on every change, including clear', () async {
      final store = InMemoryNetworkLogStore();
      final emitted = <List<String>>[];
      final sub = store.changes.listen(
        (entries) => emitted.add([for (final e in entries) e.id]),
      );

      store
        ..add(makeEntry(id: 'a'))
        ..add(makeEntry(id: 'b'))
        ..clear()
        ..clear(); // Clearing an empty store emits nothing.
      await pumpEventQueue();

      expect(emitted, [
        ['a'],
        ['b', 'a'],
        <String>[],
      ]);
      await sub.cancel();
    });

    test('keeps working after being cleared', () {
      final store = InMemoryNetworkLogStore()
        ..add(makeEntry(id: 'a'))
        ..clear()
        ..add(makeEntry(id: 'b'));
      expect(store.entries.map((e) => e.id), ['b']);
    });

    test('ignores writes after dispose', () async {
      final store = InMemoryNetworkLogStore()..add(makeEntry());
      await store.dispose();
      store
        ..add(makeEntry())
        ..clear();
      expect(store.entries, isEmpty);
    });

    test('handles many interleaved asynchronous producers', () async {
      final store = InMemoryNetworkLogStore(maxEntries: 50);
      final random = Random(7);
      await Future.wait([
        for (var i = 0; i < 200; i++)
          Future<void>.delayed(
            Duration(microseconds: random.nextInt(500)),
            () => store.add(makeEntry(id: '$i')),
          ),
      ]);

      expect(store.entries, hasLength(50));
      expect(store.entries.map((e) => e.id).toSet(), hasLength(50));
    });
  });
}
