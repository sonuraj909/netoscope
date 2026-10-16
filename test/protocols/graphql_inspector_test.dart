import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope/src/protocols/graphql/graphql_inspector.dart';
import 'package:netoscope/src/security/log_redactor.dart';

void main() {
  final inspector =
      GraphQLInspector(redactor: LogRedactor(), maxTextLength: 2000);
  final endpoint = Uri.parse('https://api.example.com/graphql');

  GraphQLDetails? post(Object? body, {Object? response, String? type}) =>
      inspector.inspectHttp(
        method: 'POST',
        url: endpoint,
        requestContentType: type ?? 'application/json',
        requestBody: body,
        responseBody: response,
      );

  test('recognizes a named query with variables', () {
    final details = post({
      'query': 'query GetUser(\$id: ID!) { user(id: \$id) { name } }',
      'operationName': 'GetUser',
      'variables': {'id': '7', 'accessToken': 'abc'},
    })!;
    final op = details.operations.single;
    expect(op.name, 'GetUser');
    expect(op.type, GraphQLOperationType.query);
    expect(op.variables, '{"id":"7","accessToken":"***"}');
    expect(details.hasData, isNull);
    expect(details.isBatch, isFalse);
  });

  test('identifies the operation type from the document', () {
    expect(
      post({'query': 'mutation Login { login { token } }'})!
          .operations
          .single
          .type,
      GraphQLOperationType.mutation,
    );
    expect(
      post({'query': '{ me { id } }'})!.operations.single.type,
      GraphQLOperationType.query,
    );
    final multi = post({
      'query': 'query A { a } mutation B { b }',
      'operationName': 'B',
    })!;
    expect(multi.operations.single.type, GraphQLOperationType.mutation);
    expect(multi.operations.single.name, 'B');
  });

  test('redacts literal secrets inside the document', () {
    final op = post({
      'query':
          'mutation { login(email: "a@b.dev", password: "hunter2", pin: 1234) { ok } }',
    })!
        .operations
        .single;
    expect(op.document, isNot(contains('hunter2')));
    expect(op.document, isNot(contains('1234')));
    expect(op.document, contains('email: "a@b.dev"'));
  });

  test('does not mistake ordinary "query" fields for GraphQL', () {
    expect(post({'query': 'running shoes', 'page': 2}), isNull);
    expect(post({'name': 'x'}), isNull);
    expect(post('not json'), isNull);
  });

  test('parses errors, paths, codes and partial data', () {
    final details = post(
      jsonEncode({'query': '{ user { email posts { title } } }'}),
      response: {
        'data': {
          'user': {'email': null}
        },
        'errors': [
          {
            'message': 'Not authorized for token=abc',
            'path': ['user', 'email'],
            'extensions': {'code': 'FORBIDDEN'},
          },
          {
            'message': 'Timeout',
            'path': ['user', 'posts', 0, 'title'],
          },
        ],
      },
    )!;
    expect(details.hasErrors, isTrue);
    expect(details.isPartial, isTrue);
    expect(details.errors.first.code, 'FORBIDDEN');
    expect(details.errors.first.message, 'Not authorized for token=***');
    expect(details.errors.last.pathLabel, 'user.posts.0.title');
  });

  test('handles batches with per-operation errors', () {
    final details = post(
      [
        {'query': 'query A { a }'},
        {'query': 'query B { b }'},
      ],
      response: utf8.encode(
        jsonEncode([
          {
            'data': {'a': 1}
          },
          {
            'data': null,
            'errors': [
              {'message': 'boom'},
            ],
          },
        ]),
      ),
    )!;
    expect(details.isBatch, isTrue);
    expect(details.operations.map((o) => o.name), ['A', 'B']);
    expect(details.errors.single.operationIndex, 1);
    expect(details.hasData, isTrue);
    expect(details.summary, 'batch (2)');
  });

  test('reads GET operations and persisted queries', () {
    final get = inspector.inspectHttp(
      method: 'GET',
      url: endpoint.replace(queryParameters: {
        'query': '{ ping }',
        'variables': '{"password":"x"}',
      }),
    )!;
    expect(get.operations.single.type, GraphQLOperationType.query);
    expect(get.operations.single.variables, '{"password":"***"}');

    final persisted = post({
      'operationName': 'Feed',
      'extensions': {
        'persistedQuery': {'version': 1, 'sha256Hash': 'abc123'},
      },
    })!;
    expect(persisted.operations.single.persistedQueryHash, 'abc123');
    expect(persisted.operations.single.type, GraphQLOperationType.unknown);
  });

  test('accepts application/graphql documents', () {
    final details = post(
      utf8.encode('subscription OnMessage { message { id } }'),
      type: 'application/graphql',
    )!;
    expect(details.operations.single.type, GraphQLOperationType.subscription);
    expect(details.operations.single.name, 'OnMessage');
  });

  test('cuts long documents', () {
    final small = GraphQLInspector(redactor: LogRedactor(), maxTextLength: 10);
    final details = small.inspectHttp(
      method: 'POST',
      url: endpoint,
      requestBody: {'query': '{ ${'a ' * 100} }'},
    )!;
    expect(details.operations.single.document, hasLength(11));
  });
}
