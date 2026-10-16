import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/src/data/export/network_log_json_exporter.dart';

import '../support/fixtures.dart';

void main() {
  test('exports entries as indented, parseable JSON', () {
    final output = exportNetworkLogsAsJson(
      [
        makeEntry(id: 'b', requestHeaders: {'authorization': '***'}),
        makeEntry(id: 'a', statusCode: 500),
      ],
      exportedAt: DateTime.utc(2026, 2, 3),
    );

    expect(output, contains('\n  "count": 2'));
    final json = jsonDecode(output) as Map<String, Object?>;
    expect(json['exportedAt'], '2026-02-03T00:00:00.000Z');
    final entries =
        (json['entries']! as List<Object?>).cast<Map<String, Object?>>();
    expect(entries.map((e) => e['id']), ['b', 'a']);
    expect(entries.first['requestHeaders'], {'authorization': '***'});
    expect(entries.last['outcome'], 'httpError');
  });

  test('exports an empty history', () {
    final json = jsonDecode(exportNetworkLogsAsJson(const [])) as Map;
    expect(json['count'], 0);
    expect(json['entries'], isEmpty);
  });
}
