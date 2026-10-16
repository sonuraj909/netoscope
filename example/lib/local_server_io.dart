import 'dart:convert';
import 'dart:io';

/// Starts a server on 127.0.0.1 that native code and `HttpClient` can call
/// without network access. Returns its base URL.
Future<Uri?> startLocalServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = await utf8.decoder.bind(request).join();
    final response = request.response..headers.contentType = ContentType.json;
    switch (request.uri.path) {
      case '/native/profile':
        response.write(
          jsonEncode({
            'id': 7,
            'name': 'Grace Hopper',
            'session_token': 'native-session-123',
          }),
        );
      case '/native/login':
        response.write(jsonEncode({'received': jsonDecode(body), 'ok': true}));
      default:
        response.statusCode = 404;
        response.write('{"error":"not found"}');
    }
    await response.close();
  });
  return Uri.parse('http://127.0.0.1:${server.port}');
}
