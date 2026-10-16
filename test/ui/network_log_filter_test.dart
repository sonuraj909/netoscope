import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/ui/network_log_filter.dart';

import '../support/fixtures.dart';

void main() {
  const slow = Duration(seconds: 1);
  final entries = [
    makeEntry(id: 'users', url: 'https://api.dev/v1/users'),
    makeEntry(
        id: 'login',
        method: 'POST',
        url: 'https://api.dev/login',
        statusCode: 401),
    makeEntry(id: 'redirect', url: 'https://api.dev/old', statusCode: 301),
    makeEntry(id: 'crash', url: 'https://api.dev/crash', statusCode: 502),
    makeEntry(
      id: 'timeout',
      url: 'https://api.dev/reports',
      statusCode: null,
      duration: const Duration(seconds: 5),
      error:
          const NetworkLogError(type: NetworkErrorType.timeout, message: 't'),
    ),
  ];

  List<String> ids(NetworkLogFilter filter) =>
      [for (final e in filter.apply(entries, slowThreshold: slow)) e.id];

  test('the default filter keeps everything in order', () {
    expect(const NetworkLogFilter().isActive, isFalse);
    expect(ids(const NetworkLogFilter()), [
      'users',
      'login',
      'redirect',
      'crash',
      'timeout',
    ]);
  });

  test('searches the URL case-insensitively', () {
    expect(ids(const NetworkLogFilter(query: ' V1/USERS ')), ['users']);
  });

  test('filters by method', () {
    expect(ids(const NetworkLogFilter(method: 'POST')), ['login']);
  });

  test('filters by status group', () {
    expect(
        ids(const NetworkLogFilter(status: StatusFilter.success)), ['users']);
    expect(ids(const NetworkLogFilter(status: StatusFilter.redirect)),
        ['redirect']);
    expect(ids(const NetworkLogFilter(status: StatusFilter.clientError)),
        ['login']);
    expect(ids(const NetworkLogFilter(status: StatusFilter.serverError)),
        ['crash']);
    expect(
        ids(const NetworkLogFilter(status: StatusFilter.failed)), ['timeout']);
  });

  test('filters slow calls', () {
    expect(ids(const NetworkLogFilter(onlySlow: true)), ['timeout']);
  });

  test('combines filters and supports clearing the method', () {
    final filter = const NetworkLogFilter(query: 'api.dev', method: 'POST')
        .copyWith(status: StatusFilter.clientError);
    expect(filter.isActive, isTrue);
    expect(ids(filter), ['login']);
    expect(filter.copyWith(clearMethod: true).method, isNull);
  });
}
