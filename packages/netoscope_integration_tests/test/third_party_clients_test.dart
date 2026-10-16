// Real third-party clients against a real loopback server.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart';
import 'package:gql_exec/gql_exec.dart' as gql;
import 'package:gql_http_link/gql_http_link.dart';
import 'package:netoscope/netoscope.dart';
import 'package:netoscope_integration_tests/user_api.dart';

void main() {
  late HttpServer server;
  late Uri base;
  late Netoscope netoscope;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final response = request.response..headers.contentType = ContentType.json;
      if (request.uri.path.startsWith('/users/')) {
        response.write(jsonEncode({'id': 7, 'name': 'Ada', 'token': 't-1'}));
      } else if (request.uri.path == '/login') {
        response.write(jsonEncode({'echo': jsonDecode(body), 'session': 's'}));
      } else if (request.uri.path == '/graphql') {
        response.write(
          jsonEncode({
            'data': {'user': null},
            'errors': [
              {
                'message': 'User not found',
                'path': ['user'],
                'extensions': {'code': 'NOT_FOUND'},
              },
            ],
          }),
        );
      } else {
        response.statusCode = 404;
      }
      await response.close();
    });
    netoscope = Netoscope(
      config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
    );
  });

  tearDown(() async {
    await netoscope.dispose();
    await server.close(force: true);
  });

  test('Retrofit (generated code on Dio)', () async {
    final dio = Dio()..interceptors.add(netoscope.dioInterceptor);
    final api = UserApi(dio, baseUrl: base.toString());

    final user = await api.getUser(7, apiKey: 'secret-key');
    await api.login({'user': 'ada', 'password': 'hunter2'});
    dio.close();

    expect(user.token, 't-1', reason: 'the app still gets real data');
    final logs = netoscope.logs.reversed.toList();
    expect(logs.map((e) => '${e.method} ${e.url.path}'), [
      'GET /users/7',
      'POST /login',
    ]);
    expect(logs.first.queryParameters['api_key'], ['***']);
    expect(logs.first.responseBody!.content, contains('"token":"***"'));
    expect(logs.last.requestBody!.content, '{"user":"ada","password":"***"}');
  });

  test('Chopper (package:http client)', () async {
    final client = chopper.ChopperClient(
      baseUrl: base,
      client: netoscope.httpClient(),
      converter: const chopper.JsonConverter(),
    );

    final user = await client.get<Map<String, dynamic>, Map<String, dynamic>>(
      Uri.parse('/users/7'),
      headers: {'Authorization': 'Bearer abc'},
    );
    await client.post<Map<String, dynamic>, Map<String, dynamic>>(
      Uri.parse('/login'),
      body: {'user': 'ada', 'password': 'hunter2'},
    );
    client.dispose();

    expect(user.body!['name'], 'Ada');
    final logs = netoscope.logs.reversed.toList();
    expect(logs, hasLength(2));
    expect(logs.first.requestHeaders['Authorization'], '***');
    expect(logs.first.statusCode, 200);
    expect(logs.last.requestBody!.content, '{"user":"ada","password":"***"}');
  });

  test('GraphQL via gql_http_link (graphql, graphql_flutter, ferry)', () async {
    final link = HttpLink(
      base.replace(path: '/graphql').toString(),
      httpClient: netoscope.httpClient(),
    );

    final response = await link
        .request(
          gql.Request(
            operation: gql.Operation(
              document: parseString(
                r'query GetUser($id: ID!, $token: String) '
                r'{ user(id: $id) { name } }',
              ),
              operationName: 'GetUser',
            ),
            variables: const {'id': '7', 'token': 'abc'},
          ),
        )
        .first;
    await link.dispose();

    expect(response.errors!.single.message, 'User not found');
    final entry = netoscope.logs.single;
    final graphQL = entry.graphQL!;
    expect(entry.outcome, NetworkLogOutcome.success);
    expect(entry.hasGraphQLErrors, isTrue);
    expect(graphQL.operations.single.name, 'GetUser');
    expect(graphQL.operations.single.type, GraphQLOperationType.query);
    expect(graphQL.operations.single.variables, '{"id":"7","token":"***"}');
    expect(graphQL.errors.single.code, 'NOT_FOUND');
    expect(graphQL.errors.single.pathLabel, 'user');
  });

  test(
    'dart:io capture adds HttpClient users without doubling these',
    () async {
      netoscope.captureDartIo();

      final dio = Dio()..interceptors.add(netoscope.dioInterceptor);
      await UserApi(dio, baseUrl: base.toString()).getUser(1);
      dio.close();

      final chopperClient = chopper.ChopperClient(
        baseUrl: base,
        client: netoscope.httpClient(),
      );
      await chopperClient.get<String, String>(Uri.parse('/users/2'));
      chopperClient.dispose();

      final raw = HttpClient();
      final request = await raw.getUrl(base.replace(path: '/users/3'));
      await (await request.close()).drain<void>();
      raw.close();

      expect(netoscope.logs.reversed.map((e) => e.url.path), [
        '/users/1',
        '/users/2',
        '/users/3',
      ]);
    },
  );
}
