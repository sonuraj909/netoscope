import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:netoscope/netoscope.dart';
import 'package:netoscope_notifications/netoscope_notifications.dart';

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
    () => _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark,
  );

  // 1. Create one logger for the whole app. Logging is automatically off in
  //    release builds unless `enabled: true` is passed.
  final _netoscope = Netoscope(
    config: const NetworkLoggerConfig(
      slowRequestThreshold: Duration(seconds: 2),
      sensitiveKeys: {'email'},
      excludedUrls: ['/health'],
      webhooks: WebhookConfig(endpoints: ['/hooks/'], maxAttempts: 3),
    ),
  );

  // 2. Attach it to Dio (add it last so it sees final headers)…
  late final Dio _dio = Dio(BaseOptions(baseUrl: 'https://demo.netoscope.dev'))
    ..httpClientAdapter = DemoBackendAdapter()
    ..interceptors.add(_netoscope.dioInterceptor);

  // 3. …and/or wrap a package:http client.
  late final http.Client _http = _netoscope.httpClient(demoHttpClient());

  @override
  void initState() {
    super.initState();
    // 5. Optional: a quiet notification with recent activity. Tapping it
    //    opens the inspector. Returns null where notifications can't run.
    unawaited(
      NetoscopeNotifications.attach(
        _netoscope,
        navigatorKey: _navigatorKey,
        // A white-on-transparent status-bar icon (android/app/src/main/res).
        androidIcon: 'ic_stat_netoscope',
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorSchemeSeed: const Color(0xFF4F6BED),
    visualDensity: VisualDensity.standard,
  );

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
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
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

  Future<void> _serverSentEvents() async {
    // package:http clients from netoscope.httpClient() record event streams
    // automatically: one entry when connected, one per event, one on close.
    final response = await widget.httpClient.send(
      http.Request('GET', Uri.parse('https://demo.netoscope.dev/events')),
    );
    await response.stream.drain<void>();
  }

  Future<void> _webSocketSession() async {
    final url = Uri.parse('wss://demo.netoscope.dev/echo');
    final socket = DemoEchoSocket();
    final recorder = widget.netoscope.webSocket(url)
      ..connected(subprotocol: 'echo');
    final incoming = recorder.observeIncoming(
      socket.stream,
      closeCode: () => socket.closeCode,
    );
    final sink = recorder.observeOutgoing(socket.sink);
    final replies = incoming.take(2).toList();
    sink
      ..add('{"type":"hello","token":"demo-session-token"}')
      ..add('ping');
    await replies;
    await socket.close();
  }

  Future<void> _webhookDelivery() => widget.dio.post<void>(
    '/hooks/orders',
    data: {'event': 'order.created', 'orderId': 42},
    options: Options(
      headers: {'x-hub-signature-256': 'sha256=5d41402abc4b2a76b9719d91'},
      extra: {
        Netoscope.webhookKey: const WebhookAttempt(
          eventType: 'order.created',
          deliveryId: 'dlv_001',
          attempt: 2,
          maxAttempts: 3,
        ),
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dio = widget.dio;
    final sections = <_DemoSection>[
      _DemoSection('REST', [
        _Demo(
          'GET /users',
          'A successful JSON response.',
          Icons.people_outline,
          () => dio.get<void>('/users'),
        ),
        _Demo(
          'POST /auth/login (redacted)',
          'Password, email, Authorization and tokens are masked.',
          Icons.lock_outline,
          () => dio.post<void>(
            '/auth/login',
            data: {'email': 'ada@example.com', 'password': 'hunter2'},
            options: Options(headers: {'Authorization': 'Basic ZGVtbzpkZW1v'}),
          ),
        ),
        _Demo(
          'GET /search?api_key=…',
          'Sensitive query parameters are masked in the URL.',
          Icons.search,
          () => dio.get<void>(
            '/search',
            queryParameters: {'q': 'flutter', 'api_key': 'secret-key'},
          ),
        ),
        _Demo(
          'package:http GET /status',
          'The same history, recorded through package:http.',
          Icons.http,
          () => widget.httpClient.get(
            Uri.parse('https://demo.netoscope.dev/status'),
          ),
        ),
      ]),
      _DemoSection('Errors & edge cases', [
        _Demo(
          'GET /orders/42 (404)',
          'An HTTP error response.',
          Icons.report_gmailerrorred,
          () => dio.get<void>('/orders/42'),
        ),
        _Demo(
          'GET /reports/annual (slow)',
          'Takes 2.5 s and is flagged as slow.',
          Icons.speed,
          () => dio.get<void>('/reports/annual'),
        ),
        _Demo(
          'GET /flaky (timeout)',
          'A receive timeout, still delivered to your code.',
          Icons.timer_off_outlined,
          () => dio.get<void>('/flaky'),
        ),
        _Demo(
          'GET /long-poll (cancelled)',
          'Cancelled by a CancelToken after 600 ms.',
          Icons.cancel_outlined,
          _cancelledRequest,
        ),
        _Demo(
          'GET /health (excluded)',
          'Matches excludedUrls, so it is not recorded.',
          Icons.visibility_off_outlined,
          () => dio.get<void>('/health'),
        ),
      ]),
      _DemoSection('Protocols', [
        _Demo(
          'GraphQL query (partial errors)',
          'Data with an error on viewer.email.',
          Icons.hub_outlined,
          () => dio.post<void>(
            '/graphql',
            data: {
              'query': 'query Viewer { viewer { id name email } }',
              'operationName': 'Viewer',
            },
          ),
        ),
        _Demo(
          'SSE stream (3 events)',
          'Server-Sent Events, recorded as they arrive.',
          Icons.podcasts,
          _serverSentEvents,
        ),
        _Demo(
          'WebSocket echo (simulated)',
          'Open, two messages each way, close.',
          Icons.swap_vert,
          _webSocketSession,
        ),
        _Demo(
          'Webhook delivery (503, retryable)',
          'Attempt 2 of 3; the signature is never stored.',
          Icons.webhook,
          _webhookDelivery,
        ),
      ]),
    ];

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Netoscope',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Network inspector demo',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.isDark ? 'Light theme' : 'Dark theme',
            icon: Icon(
              widget.isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: 'Open inspector',
            icon: const Icon(Icons.manage_search),
            onPressed: () => widget.netoscope.openInspector(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _StatusCard(
            status: _status,
            netoscope: widget.netoscope,
            onOpenInspector: () => widget.netoscope.openInspector(context),
          ),
          const SizedBox(height: 12),
          _ControlsCard(netoscope: widget.netoscope),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
              child: Text(
                section.title.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  for (final (index, demo) in section.demos.indexed) ...[
                    if (index > 0) const Divider(height: 1, indent: 64),
                    _DemoTile(
                      demo: demo,
                      onRun: () => _run(demo.label, demo.run),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Demo {
  const _Demo(this.label, this.description, this.icon, this.run);

  final String label;
  final String description;
  final IconData icon;
  final Future<Object?> Function() run;
}

class _DemoSection {
  const _DemoSection(this.title, this.demos);

  final String title;
  final List<_Demo> demos;
}

class _DemoTile extends StatelessWidget {
  const _DemoTile({required this.demo, required this.onRun});

  final _Demo demo;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onRun,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(demo.icon, size: 20, color: scheme.onPrimaryContainer),
      ),
      title: Text(
        demo.label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(demo.description),
      trailing: Icon(Icons.play_arrow_rounded, color: scheme.primary),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.netoscope,
    required this.onOpenInspector,
  });

  final String status;
  final Netoscope netoscope;
  final VoidCallback onOpenInspector;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer.withAlpha(110),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 34),
                // The same history the inspector reads, observed live.
                Expanded(
                  child: StreamBuilder<List<NetworkLogEntry>>(
                    stream: netoscope.logChanges,
                    initialData: netoscope.logs,
                    builder: (context, snapshot) => Text(
                      '${snapshot.data?.length ?? 0} requests recorded',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onOpenInspector,
                  icon: const Icon(Icons.manage_search, size: 18),
                  label: const Text('Inspect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Runtime on/off switches. Each calls the matching `Netoscope` method:
/// `setLoggingEnabled`, `setFloatingButtonEnabled`, `setNotificationEnabled`.
class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.netoscope});

  final Netoscope netoscope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: StreamBuilder<NetoscopeSettings>(
        stream: netoscope.settingsChanges,
        initialData: netoscope.settings,
        builder: (context, _) {
          final settings = netoscope.settings;
          return Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.fiber_manual_record_outlined),
                title: const Text('Recording'),
                subtitle: const Text('Pause or resume capture'),
                value: settings.recording,
                onChanged: netoscope.setLoggingEnabled,
              ),
              const Divider(height: 1, indent: 64),
              SwitchListTile(
                secondary: const Icon(Icons.bubble_chart_outlined),
                title: const Text('Floating button'),
                subtitle: const Text('Shortcut to the inspector'),
                value: settings.floatingButton,
                onChanged: netoscope.setFloatingButtonEnabled,
              ),
              const Divider(height: 1, indent: 64),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_none),
                title: const Text('Notification'),
                subtitle: Text(
                  netoscope.hasNotifier
                      ? 'Recent activity · tap to inspect'
                      : 'Not available on this platform',
                ),
                value: netoscope.hasNotifier && settings.notification,
                onChanged: netoscope.hasNotifier
                    ? netoscope.setNotificationEnabled
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }
}
