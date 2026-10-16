import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:netoscope/netoscope.dart';

import 'demo_backend.dart';

void main() => runApp(const NetoscopeExampleApp());

class NetoscopeExampleApp extends StatefulWidget {
  const NetoscopeExampleApp({super.key});

  @override
  State<NetoscopeExampleApp> createState() => _NetoscopeExampleAppState();
}

class _NetoscopeExampleAppState extends State<NetoscopeExampleApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() => setState(
        () => _themeMode =
            _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      );

  // 1. Create one logger for the whole app. Logging is automatically off in
  //    release builds unless `enabled: true` is passed.
  final _netoscope = Netoscope(
    config: const NetworkLoggerConfig(
      slowRequestThreshold: Duration(seconds: 2),
      sensitiveKeys: {'email'},
      excludedUrls: ['/health'],
    ),
  );

  // 2. Attach it to Dio (add it last so it sees final headers)…
  late final Dio _dio = Dio(BaseOptions(baseUrl: 'https://demo.netoscope.dev'))
    ..httpClientAdapter = DemoBackendAdapter()
    ..interceptors.add(_netoscope.dioInterceptor);

  // 3. …and/or wrap a package:http client.
  late final http.Client _http = _netoscope.httpClient(demoHttpClient());

  @override
  void dispose() {
    _http.close();
    _dio.close();
    _netoscope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Netoscope example',
      navigatorKey: _navigatorKey,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      // 4. Optional: a floating button that opens the inspector everywhere.
      builder: (context, child) => NetworkInspectorOverlay(
        netoscope: _netoscope,
        navigatorKey: _navigatorKey,
        child: child!,
      ),
      home: DemoScreen(
        netoscope: _netoscope,
        dio: _dio,
        httpClient: _http,
        isDark: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class DemoScreen extends StatefulWidget {
  const DemoScreen({
    super.key,
    required this.netoscope,
    required this.dio,
    required this.httpClient,
    required this.isDark,
    required this.onToggleTheme,
  });

  final Netoscope netoscope;
  final Dio dio;
  final http.Client httpClient;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  String _status = 'Tap a request to send it.';

  Future<void> _run(String label, Future<Object?> Function() request) async {
    setState(() => _status = '$label…');
    try {
      await request();
      _setStatus('$label: done');
    } on DioException catch (error) {
      // Netoscope never swallows errors: your own handling still runs.
      _setStatus('$label: ${error.type.name}');
    }
  }

  void _setStatus(String status) {
    if (mounted) setState(() => _status = status);
  }

  Future<void> _cancelledRequest() async {
    final token = CancelToken();
    Future<void>.delayed(const Duration(milliseconds: 600), token.cancel);
    await widget.dio.get<void>('/long-poll', cancelToken: token);
  }

  @override
  Widget build(BuildContext context) {
    final dio = widget.dio;
    final requests = <(String, Future<Object?> Function())>[
      ('GET /users', () => dio.get<void>('/users')),
      (
        'POST /auth/login (redacted)',
        () => dio.post<void>(
              '/auth/login',
              data: {'email': 'ada@example.com', 'password': 'hunter2'},
              options:
                  Options(headers: {'Authorization': 'Basic ZGVtbzpkZW1v'}),
            ),
      ),
      (
        'GET /search?api_key=…',
        () => dio.get<void>(
              '/search',
              queryParameters: {'q': 'flutter', 'api_key': 'secret-key'},
            ),
      ),
      ('GET /orders/42 (404)', () => dio.get<void>('/orders/42')),
      ('GET /reports/annual (slow)', () => dio.get<void>('/reports/annual')),
      ('GET /flaky (timeout)', () => dio.get<void>('/flaky')),
      ('GET /long-poll (cancelled)', _cancelledRequest),
      ('GET /health (excluded)', () => dio.get<void>('/health')),
      (
        'package:http GET /status',
        () => widget.httpClient
            .get(Uri.parse('https://demo.netoscope.dev/status')),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Netoscope example'),
        actions: [
          IconButton(
            tooltip: widget.isDark ? 'Light theme' : 'Dark theme',
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: 'Open inspector',
            icon: const Icon(Icons.manage_search),
            onPressed: () => widget.netoscope.openInspector(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(_status, style: Theme.of(context).textTheme.titleMedium),
          // The same history the inspector reads, observed live.
          StreamBuilder<List<NetworkLogEntry>>(
            stream: widget.netoscope.logChanges,
            initialData: widget.netoscope.logs,
            builder: (context, snapshot) =>
                Text('${snapshot.data?.length ?? 0} requests recorded'),
          ),
          const SizedBox(height: 16),
          for (final (label, request) in requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () => _run(label, request),
                child: Text(label),
              ),
            ),
        ],
      ),
    );
  }
}
