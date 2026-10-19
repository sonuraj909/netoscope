# Netoscope

A network logger and HTTP inspector for Flutter, for debug builds.

Netoscope records what your app sends and receives over HTTP (through
**Dio** or **`package:http`**). It also covers GraphQL, Server-Sent Events,
WebSockets, gRPC(-Web), MQTT and webhooks. Secrets are redacted before
anything is printed, stored, shown or exported. History is kept in a bounded
in-memory store, and an optional in-app inspector lets you browse it.

<p>
  <img src="https://raw.githubusercontent.com/sonuraj909/netoscope/main/screenshots/request_list.webp" width="160" alt="Request list">
  <img src="https://raw.githubusercontent.com/sonuraj909/netoscope/main/screenshots/request_detail.webp" width="160" alt="Request details with redaction">
  <img src="https://raw.githubusercontent.com/sonuraj909/netoscope/main/screenshots/json_tree.webp" width="160" alt="JSON tree viewer">
  <img src="https://raw.githubusercontent.com/sonuraj909/netoscope/main/screenshots/timeline.webp" width="160" alt="Timeline">
  <img src="https://raw.githubusercontent.com/sonuraj909/netoscope/main/screenshots/statistics.webp" width="160" alt="Statistics">
</p>

> **Netoscope is a debugging aid, not a production observability tool.**
> Logging is off in release builds by default. See
> [Security considerations](#security-considerations).

## Quick start

```sh
flutter pub add netoscope
```

```dart
final netoscope = Netoscope();
final dio = Dio()..interceptors.add(netoscope.dioInterceptor);

// Anywhere below your Navigator:
netoscope.openInspector(context);
```

That's it: every request, response and error is now in the inspector, with
passwords, tokens and cookies redacted. Using `package:http` instead? Use
`netoscope.httpClient()`. See [Inspector](#inspector) for a floating button.

## Contents

- [What is supported](#what-is-supported)
- [Installation](#installation)
- [Switching from another network logger](#switching-from-another-network-logger)
- [HTTP: Dio and package:http](#http-dio-and-packagehttp)
- [Client compatibility](#client-compatibility)
- [dart:io HttpClient](#dartio-httpclient)
- [Console-only setup](#console-only-setup)
- [Inspector](#inspector)
- [Deep inspection](#deep-inspection): search syntax, tags, duplicates & N+1,
  statistics, timeline
- [History persistence & export](#history-persistence--export)
- [Native capture (Android & iOS)](#native-capture-android--ios)
- [Runtime switches](#runtime-switches)
- [Notification](#notification)
- [Configuration](#configuration)
- [Redaction](#redaction)
- [Payload inspection and decoders](#payload-inspection-and-decoders)
- [GraphQL](#graphql)
- [Real-time protocols](#real-time-protocols)
- [Webhooks](#webhooks)
- [Event model](#event-model)
- [Architecture](#architecture)
- [Example](#example) · [Testing](#testing) · [Limitations](#limitations) ·
  [Security considerations](#security-considerations)

## What is supported

"Automatic" means Netoscope observes the traffic itself once you attach it.
"Recorder" means Netoscope has no dependency on that protocol's client
library: you call a small recording API from your client's callbacks or
streams.

| Protocol | How | Notes |
| --- | --- | --- |
| HTTP via Dio | Automatic (`netoscope.dioInterceptor`) | Includes upload/download progress when the app sets progress callbacks |
| HTTP via `package:http` | Automatic (`netoscope.httpClient()`) | |
| Retrofit, Chopper, GraphQL clients, `cupertino_http`, `cronet_http` | Automatic, through the Dio or `http` hook they are built on | See [Client compatibility](#client-compatibility) |
| `dart:io` `HttpClient` | Automatic after `netoscope.captureDartIo()` | Also covers `Image.network` and SDKs; not on the web |
| Native Android (OkHttp) & iOS (`URLSession`) | `netoscope_native` plugin | Native code and SDKs; see [Native capture](#native-capture-android--ios) |
| GraphQL over HTTP | Automatic, through either HTTP integration | Operations, variables, errors, partial data, batches, persisted queries, multipart uploads |
| GraphQL over WebSocket | Automatic, with `WebSocketRecorder` | `graphql-transport-ws` and `subscriptions-transport-ws` messages |
| Server-Sent Events | Automatic with `netoscope.httpClient()`; recorder for other clients | Events are recorded as they arrive; the stream is not buffered |
| WebSocket | Recorder (`netoscope.webSocket`) wrapping any `Stream`/`StreamSink` | Works with `web_socket_channel` or `dart:io` `WebSocket` without depending on them |
| gRPC-Web (binary) | Automatic, through either HTTP integration | Service, method, status and message counts from frames and trailers |
| gRPC (native, `package:grpc`) | Recorder (`netoscope.grpcCall`) | Call it from a `ClientInterceptor`; see the [recipe](#grpc) |
| MQTT | Recorder (`netoscope.mqtt`) | Call it from your MQTT client's callbacks |
| Outbound webhooks | Automatic for configured endpoints or tagged Dio requests | Attempt, outcome, retryability; signatures are never stored |
| Incoming / backend webhooks | Import (`netoscope.importWebhookDeliveries`) | A Flutter app cannot see server-to-server traffic |
| Protocol Buffers payloads | Decoder you supply (`ProtobufPayloadDecoder`) | Without a schema, protobuf is shown as binary |
| Other protocols | Recorder (`netoscope.connection`) | |

**Not supported:**
- Native gRPC over Dio or `package:http`. Those clients cannot expose HTTP/2 trailers.
- Decompressing gRPC messages.
- Decoding `application/grpc-web-text` (base64).
- Observing sockets that the app does not route through a recorder.

## Installation

```sh
flutter pub add netoscope
```

```dart
import 'package:netoscope/netoscope.dart';
```

Requires Dart `>=3.5.0 <4.0.0` and Flutter `>=3.24.0`. Netoscope depends on
`dio` (`^5.4.0`) and `http` (`^1.5.0`), both pure Dart. It does **not**
depend on any WebSocket, gRPC, MQTT or protobuf package.

## Switching from another network logger

If your app already uses a network logger or HTTP inspector such as Alice,
`pretty_dio_logger` or a custom logging interceptor, moving to Netoscope is
usually a two-line change:

1. Replace the logger's Dio interceptor with `netoscope.dioInterceptor`, or
   wrap your `http.Client` with `netoscope.httpClient(client)`.
2. Replace the call that opened the old logger's screen with
   `netoscope.openInspector(context)`, or add `NetworkInspectorOverlay` for a
   floating button.

Netoscope only observes traffic, so you can run it next to your current logger
while you compare them, then remove the old one. What you get on top of
request logging:

- Redaction of secrets before anything is printed, stored, shown or exported.
- GraphQL, WebSocket, SSE, gRPC, MQTT and webhook events in the same list.
- Search syntax (`status:5xx method:POST duration:>500ms`), tags, a timeline,
  statistics, and duplicate and N+1 detection.
- cURL, JSON and HAR export, optional persisted history, a notification and
  native Android/iOS capture.

## HTTP: Dio and package:http

Create **one** `Netoscope` for the app and attach it to your clients:

```dart
final netoscope = Netoscope();

final dio = Dio()
  // Add Netoscope last so it sees headers added by other interceptors.
  ..interceptors.add(netoscope.dioInterceptor);

final client = netoscope.httpClient();              // wraps http.Client()
final custom = netoscope.httpClient(myRetryClient); // or wraps your client
```

Both integrations only observe. Requests, responses and errors are passed on
unchanged; `DioException`s and `package:http` exceptions still reach your code.
Response streams are read only as your code reads them.

To keep a single Dio request out of the logs:

```dart
dio.get('/metrics', options: Options(extra: {Netoscope.skipLoggingKey: true}));
```

**Transfer progress (Dio):** if a request already has `onSendProgress` or
`onReceiveProgress`, Netoscope records how far the upload or download got.
This includes cancelled downloads. Your callback still runs first, with the
same arguments. No callback is added to requests that have none. Turn this off
with `captureTransferProgress: false`.

## Client compatibility

Netoscope hooks into Dio and `package:http`. Most Dart HTTP clients are built
on one of the two, so one line of setup covers them.

| Client | Setup | Verified |
| --- | --- | --- |
| **Dio** | `dio.interceptors.add(netoscope.dioInterceptor)` | ✅ tests |
| **Retrofit** (`retrofit`) | Add the interceptor to the Dio you pass to the generated API | ✅ integration test with generated code |
| **`package:http`** | `netoscope.httpClient()` / `netoscope.httpClient(inner)` | ✅ tests |
| **Chopper** | `ChopperClient(client: netoscope.httpClient(), …)` | ✅ integration test |
| **`graphql` / `graphql_flutter`** | `HttpLink(url, httpClient: netoscope.httpClient())` | ✅ via `gql_http_link` integration test |
| **`ferry`** | `HttpLink(url, httpClient: netoscope.httpClient())` (`gql_http_link`) | ✅ via `gql_http_link` integration test |
| **`cupertino_http`, `cronet_http`** | `netoscope.httpClient(CupertinoClient.defaultSessionConfiguration())` | Not tested here (native) |
| **`dart:io` `HttpClient`**, `Image.network`, SDKs | `netoscope.captureDartIo()` | ✅ tests over real sockets |

```dart
// Retrofit
final dio = Dio()..interceptors.add(netoscope.dioInterceptor);
final api = UserApi(dio, baseUrl: 'https://api.example.com');

// Chopper
final chopper = ChopperClient(
  baseUrl: Uri.parse('https://api.example.com'),
  client: netoscope.httpClient(),
  converter: const JsonConverter(),
);

// graphql / graphql_flutter / ferry
final link = HttpLink(
  'https://api.example.com/graphql',
  httpClient: netoscope.httpClient(),
);
```

The integration tests live in
[`packages/netoscope_integration_tests`](packages/netoscope_integration_tests).
They run Retrofit (with generated code), Chopper and `gql_http_link` against
a local server.

## dart:io HttpClient

Code that uses `HttpClient` directly isn't seen by the Dio or `http` hooks.
That includes your own code, Flutter's `Image.network` and many SDKs.
Capture it with one call, as early as possible, for example at the start of
`main`:

```dart
final netoscope = Netoscope();
netoscope.captureDartIo(); // returns false on the web or when disabled
```

How it works:
- **Global wrapper:** it installs a `HttpOverrides` that wraps every
  `HttpClient` created afterwards. An existing `HttpOverrides` (for example a
  proxy or certificate setup) keeps working underneath. `stopCapturingDartIo()`
  restores it.
- **No duplicates:** Dio's default adapter and `package:http`'s `IOClient`
  also use `HttpClient`. Calls already recorded by `dioInterceptor` or
  `httpClient()` are skipped.
- **Pass-through:** requests and responses go through unchanged. Bodies are
  observed as the app reads them.
- **Media:** responses such as images are counted, not buffered.
- **Event streams:** `text/event-stream` responses are recorded as SSE.

Limitations:
- `HttpClient`s created before `captureDartIo()` aren't wrapped.
- Code that sets its own `HttpOverrides` later replaces the wrapper.
- The duplicate check matches method and URL, so two identical calls opened
  at the same moment by different layers may be attributed to one.
- Not available on the web. Browser `fetch`/XHR calls aren't visible to Dart.

## Console-only setup

The inspector is optional. Without it, Netoscope writes one line per event to
the debug console:

```dart
final netoscope = Netoscope(
  config: const NetworkLoggerConfig(
    showInspector: false,
    consoleLogLevel: ConsoleLogLevel.summary, // or .verbose for headers/bodies
  ),
);
```

```
POST https://api.example.com/graphql → 200 (120 ms) [GraphQL query Viewer, 1 errors]
GET https://api.example.com/reports → 200 (3412 ms) [SLOW]
WS ↓ wss://rt.example.com/socket (JSON)
SSE closed https://rt.example.com/feed (60123 ms)
POST https://hooks.partner.dev/orders → 503 (201 ms) [webhook retryable]
```

With `ConsoleLogLevel.verbose`, headers, pretty-printed bodies and protocol
details are listed below each line. Set `consoleColors: true` to color
statuses, methods and tags with ANSI codes, for consoles that render them.

Output goes through `dart:developer`'s `log`, which appears in IDE debug
consoles and DevTools. To send it somewhere else, such as `debugPrint`, use
your own sink:

```dart
final netoscope = Netoscope(
  config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
  sinks: [ConsoleNetworkLogSink(output: debugPrint)],
);
```

## Inspector

Open it from anywhere below your `Navigator`:

```dart
IconButton(
  icon: const Icon(Icons.network_check),
  onPressed: () => netoscope.openInspector(context),
)
```

Or add a floating button over the whole app:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => NetworkInspectorOverlay(
    netoscope: netoscope,
    navigatorKey: navigatorKey,
    child: child!,
  ),
  home: const HomePage(),
);
```

The inspector follows your app's theme brightness. Switch it to light or dark
from the inspector's settings (the gear icon), or set the initial mode, for
example a dark inspector in a light-only app:

```dart
final netoscope = Netoscope(
  config: const NetworkLoggerConfig(
    inspectorThemeMode: InspectorThemeMode.dark,
  ),
);
```

`NetworkInspectorButton` is also available on its own, and `NetworkInspector`
is a regular widget you can embed. These widgets render nothing, or just
`child`, when the inspector is unavailable, so they can stay in release builds.

The inspector provides:

- **List:** method or protocol badge (`GET`, `WS ↑`, `SSE ↓`, `MQTT open`,
  `gRPC-Web`), path or operation, status, duration or size, and a `GQL ERR`
  marker for GraphQL errors.
- **Search:** across URLs, GraphQL operation names, SSE event types, MQTT
  topics and gRPC methods.
- **Quick filters:** status group (2xx–5xx, Failed), method, and slow calls.
- **Filters sheet:** protocol, time range, GraphQL only or GraphQL errors,
  message direction, SSE event type and payload format.
- **Details:**
  - An Overview tab with protocol details.
  - Request/Response tabs for calls, a Payload tab for messages, and a
    Handshake tab for connections.
  - A GraphQL tab listing operations, variables and errors with their paths.
  - **View connection events**, which lists every event of a connection.
- **Copy and export:**
  - Copy one call as **cURL** or JSON, from its detail screen or by
    long-pressing its row.
  - Export the whole history as JSON.
  - Clear the history after a confirmation.
- **Payload views:** JSON, XML/HTML, GraphQL and form bodies are
  syntax-highlighted with line numbers and a wrap toggle. JSON can switch to a
  collapsible **Tree** view. Redacted values are highlighted, so you can see
  what was masked.

cURL commands are built from the captured, already-redacted data. Masked
values appear as `***`, and the confirmation says so; replace them before
running the command. Binary, streamed and truncated bodies are left out.

Large bodies are pretty-printed in a background isolate (on platforms other
than web) and long bodies are rendered lazily, line by line. Bodies are
already bounded by `maxBodySize`.

### Custom payload viewers

```dart
class CsvViewer extends PayloadViewer {
  const CsvViewer();

  @override
  bool canView(NetworkLogBody body) =>
      body.contentType?.startsWith('text/csv') ?? false;

  @override
  Widget build(BuildContext context, NetworkLogBody body) =>
      MyCsvTable(csv: body.content);
}

netoscope.openInspector(context, payloadViewers: const [CsvViewer()]);
```

`NetworkInspector`, `NetworkInspectorButton` and `NetworkInspectorOverlay`
accept the same `payloadViewers` parameter.

## Deep inspection

### Search syntax

The search box accepts free text and `key:value` filters. Every term must
match; commas separate alternatives; `-` or `!` negates a term; quote values
with spaces. Tap **?** in the search box for a cheat sheet.

```
method:POST status:>=400                 failed writes
host:api.example.com duration:>500       slow calls to one host
is:n+1                                   calls in an N+1 burst
tag:checkout -status:2xx                 problems in the checkout flow
op:GetUser is:error                      a failing GraphQL operation
body:"not found"  header:authorization   body text, header names
protocol:ws,sse  source:ios  size:>100kb
```

| Key | Values |
| --- | --- |
| `method:` | `GET`, `post,put` |
| `status:` | `404`, `4xx`, `>=500`, `200-299`, `ok`, `error`, `cancelled` |
| `host:` `path:` `url:` | part of the URL |
| `duration:` | `>500`, `>=1s`, `100-300ms` |
| `size:` | response size: `>10kb`, `<1mb` |
| `protocol:` | `http`, `ws`, `sse`, `grpc`, `mqtt` |
| `tag:` | a tag set in code |
| `is:` | `slow`, `error`, `success`, `graphql`, `duplicate`, `n+1`, `cancelled`, `message`, `connection`, `webhook`, `tagged` |
| `op:` | GraphQL operation name |
| `header:` `body:` | header name, body text |
| `event:` `topic:` `source:` | SSE event type, MQTT topic, native source |

The **Filters** sheet also offers tags and duplicate/N+1 toggles as chips.

### Tagging calls

```dart
// Tag everything inside a flow, across Dio, http, dart:io and recorders,
// including async continuations.
await netoscope.tagged('login-flow', () async {
  await api.login();
  await api.loadProfile();
});

netoscope.addTag('checkout');    // tag every call until removed
netoscope.removeTag('checkout');

dio.get('/cart', options: Options(extra: {Netoscope.tagsKey: 'cart'})); // one request
```

Tags appear as `#tag` in rows and details, in exports, and in `tag:`
searches.

### Duplicate and N+1 detection

Netoscope flags two patterns automatically:
- **Duplicates:** identical requests (method, URL and body) repeated within a
  short window.
- **N+1:** a burst of calls to one endpoint pattern that differ only by an ID,
  such as `GET /users/{id}` five or more times. IDs are recognized as numbers,
  UUIDs, hex and token-like segments.

Flagged calls get **DUP** or **N+1** badges, an explanation with a suggested
fix in their details, and a "Show all" link to the whole group. They're also
available programmatically:

```dart
final insights = netoscope.analyzeTraffic();
for (final group in insights.nPlusOne) {
  print('${group.pattern}: ${group.count} calls in ${group.span}');
}
```

Tune detection with `NetworkLoggerConfig(trafficAnalyzer: TrafficAnalyzer(
window: …, duplicateThreshold: …, nPlusOneThreshold: …))`.

### Statistics

The **Statistics** screen (chart icon) updates live and shows:
- **Headline numbers:** requests, success rate, average and p95 latency,
  data received and sent, slow and failed counts.
- **A status-code ratio bar.**
- **Breakdowns by method, protocol and host.**
- **The slowest and most-called endpoints.**
- **Redundant-traffic findings.**

The same numbers are available as `netoscope.statistics()`.

### Timeline

The **Timeline** screen is a Gantt view of the calls in the current filter:
- **Bars:** each call is a bar from start to end, colored by outcome and
  labelled with its duration.
- **Connections and events:** connections appear as lifetime bars, and
  messages and other events as dots.
- **Controls:** zoom with the buttons or a pinch, use **Fit** to see
  everything, and tap a row to open the call.

## History persistence & export

History is in memory by default. To keep it across restarts, use a
persistent store. History is written debounced and atomically, and corrupt
files are ignored:

```dart
final dir = await getApplicationSupportDirectory(); // package:path_provider
final store = await PersistentNetworkLogStore.open(
  FileNetworkLogPersistence('${dir.path}/netoscope_history.json'),
  maxEntries: 200,
);
final netoscope = Netoscope(store: store);
```

Persisted entries are the already-redacted ones, but they can still contain
personal data. Only persist where that is acceptable. To store history
elsewhere, implement `NetworkLogPersistence`.

**Export.** The inspector's **⋮** menu copies the history as JSON or as
**HAR 1.2**, which Chrome DevTools, Charles, Proxyman and Postman can import.
From code, use `netoscope.exportJson()` and `netoscope.exportHar()`. To offer
**Share…**, provide a handler. Netoscope itself doesn't depend on a share
plugin:

```dart
final netoscope = Netoscope(
  exportHandler: (export) => SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(utf8.encode(export.content),
        mimeType: export.mimeType, name: export.fileName)],
  )),
);
```

## Native capture (Android & iOS)

The [`netoscope_native`](packages/netoscope_native) plugin records calls made
by native code and SDKs into the same history. They are redacted in Dart and
labelled with `source: android` or `source: ios`:

```dart
await NetoscopeNative.attach(netoscope, captureAllUrlSessions: true);
```

- **Android:** add `NetoscopeInterceptor()` to your OkHttp clients.
- **iOS:** `URLSession.shared` is captured automatically.
  `captureAllUrlSessions` also covers sessions created from
  `.default`/`.ephemeral` configurations.

Verified by an integration test on the Android emulator and the iOS
simulator. See the plugin README for limitations.
Other native sources can be recorded with `netoscope.recordExternalCall(…)`.

## Runtime switches

Recording, the floating button, the notification and the inspector theme
(system, light or dark) can be switched while the app runs, from code or from the inspector's **settings** panel
(the gear icon):

```dart
netoscope.setLoggingEnabled(false);        // pause capture; history is kept
netoscope.setLoggingEnabled(true);         // resume
netoscope.setFloatingButtonEnabled(false); // hide the floating button
netoscope.setNotificationEnabled(true);    // show the activity notification
netoscope.setInspectorThemeMode(InspectorThemeMode.dark); // or .light / .system

netoscope.settings;          // NetoscopeSettings(recording, floatingButton, notification, themeMode)
netoscope.settingsChanges;   // Stream<NetoscopeSettings>
netoscope.isRecording;       // false while paused
```

Initial values come from `NetworkLoggerConfig.showFloatingButton`,
`showNotification` and `inspectorThemeMode`. While recording is paused, the inspector shows a
**Recording paused · Resume** banner.

These are runtime conveniences, not a security control. A logger that is
disabled for the build (the release default) stays off, and these methods
are ignored.

## Notification

Netoscope can show recent activity in a quiet notification. Tapping it
opens the inspector, from anywhere in the app or from the background.

The core package defines the `NetworkActivityNotifier` contract.
Notifications need a native plugin, so a ready-made implementation lives in
the companion package
[`netoscope_notifications`](packages/netoscope_notifications), built on
`flutter_local_notifications`. Apps that don't want notifications don't take
on that plugin or its platform setup.

```dart
final navigatorKey = GlobalKey<NavigatorState>();
final netoscope = Netoscope();

// After WidgetsFlutterBinding.ensureInitialized(), for example in initState:
await NetoscopeNotifications.attach(netoscope, navigatorKey: navigatorKey);
```

How the notification behaves:
- **Content:** the request count, a status header ("All OK", "N failed",
  "Paused") and a `✓/✕` line per recent call with method, status, path and
  duration.
- **Actions:** **Open**, **Pause/Resume** and **Clear**.
- **Update rate:** at most one update per second
  (`Netoscope(notificationInterval: …)`).
- **Android:** an ongoing, silent notification in a low-importance channel.
- **iOS/macOS:** a passive Notification Center entry with no banner or sound,
  unless `showBanner: true`.
- **Removal:** it is removed when notifications are switched off, the
  history is cleared, or `netoscope.dispose()` is called.

The companion package needs platform setup: Android core-library desugaring
and an iOS `AppDelegate` line. See its README. To use a different
notification mechanism, implement `NetworkActivityNotifier` and pass it to
`Netoscope(notifier: …)` or `netoscope.attachNotifier(…)`.

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `null` | `null` logs in debug/profile and **not** in release. `true`/`false` force it. |
| `consoleLogLevel` | `summary` | `none`, `summary` or `verbose` (adds headers, bodies and protocol details). |
| `consoleColors` | `false` | ANSI colors in console output. |
| `showInspector` | `true` | Whether the inspector, button and overlay are available. |
| `showFloatingButton` | `true` | Initial state of the floating-button switch. |
| `showNotification` | `true` | Initial state of the notification switch (when a notifier is attached). |
| `inspectorThemeMode` | `system` | Initial inspector theme: `system` follows the app's brightness; `light` or `dark` force one. Switchable at runtime. |
| `maxHistorySize` | `100` | Events kept in memory; the oldest are evicted. |
| `maxBodySize` | `32768` | Characters kept per body (also caps GraphQL documents and variables). `0` keeps only the format. |
| `captureRequestBody` / `captureResponseBody` | `true` | Capture bodies (and outgoing/incoming message payloads). |
| `captureHeaders` | `true` | Capture request and response headers. |
| `excludedUrls` | `[]` | `String` (substring) or `RegExp` patterns; matching URLs are not logged. |
| `slowRequestThreshold` | `3 s` | Exchanges at least this long are flagged as slow. |
| `sensitiveKeys` | `{}` | Extra keys to redact, in addition to the built-in list. |
| `redactionMask` | `'***'` | Replacement for redacted values. |
| `payloadDecoders` | `[]` | Custom `PayloadDecoder`s, such as `ProtobufPayloadDecoder`. |
| `detectGraphQL` | `true` | Recognize GraphQL operations and errors. |
| `webhooks` | `WebhookConfig()` | Which requests are webhook deliveries, and the header names to read. |
| `captureTransferProgress` | `true` | Record Dio upload/download progress for requests that report it. |
| `captureRealtimeMessages` | `true` | Record individual WebSocket/SSE/MQTT/gRPC-stream messages. Lifecycle events are always recorded. |

Worst-case memory is roughly `maxHistorySize × 2 bodies × maxBodySize`
characters, about 13 MB with the defaults. Busy real-time connections evict
older history quickly. Use `ignoreMessage` (for example for heartbeats),
`excludedUrls` or `captureRealtimeMessages: false` to keep useful history
around.

## Redaction

Redaction runs inside the adapters and recorders, **before** an entry is
printed, stored, shown or exported. It applies to:
- Header names, query parameter names and JSON keys at any depth.
- GraphQL variables and literal arguments in GraphQL documents.
- XML/HTML elements and attributes.
- Form fields, multipart fields and message payloads.

Matching ignores case, `-`, `_`, `.` and spaces.

A key is redacted when it:
- **contains** `authorization`, `cookie`, `password`, `passwd`,
  `passphrase`, `secret`, `token`, `apikey`, `credential`, `session`,
  `privatekey` or `signature`, or
- **equals** `otp`, `otpcode`, `pin`, `pwd`, `cvv`, `cvc`, `ssn`, `auth`,
  `jwt` or `sig`, or
- equals one of your `sensitiveKeys`.

URL credentials (`https://user:pass@host`), `Bearer`/`Basic` credentials in
free text and error messages, and HTML inputs whose `name` is sensitive (such
as `<input name="csrf_token" value="…">`) are masked too.

```dart
final netoscope = Netoscope(
  config: const NetworkLoggerConfig(
    sensitiveKeys: {'national_id', 'date_of_birth'},
    redactionMask: '[redacted]',
  ),
);
```

```jsonc
// Sent:   {"email": "ada@example.com", "password": "hunter2", "profile": {"national_id": "X1"}}
// Logged: {"email": "ada@example.com", "password": "[redacted]", "profile": {"national_id": "[redacted]"}}
```

Redaction is by key. A secret sent under an innocuous name, such as a GraphQL
variable called `$p` holding a password, is not detected. Add such keys to
`sensitiveKeys`.

## Payload inspection and decoders

Each payload goes through the same pipeline:

1. **Detect the format.** The declared content type comes first, with
   sniffing as a fallback: JSON, XML, HTML, form, multipart, protobuf, text,
   binary.
2. **Decode** with your registered `PayloadDecoder`s.
3. **Redact.** Structures are redacted by key; text, forms and markup by pattern.
4. **Serialize and truncate.**

Netoscope never mutates the original payload, never listens to streams it was
not asked to observe, and never decodes binary data unless a decoder asks for
it. Payloads larger than 1 MiB are not parsed; they are redacted by pattern
and truncated.

| Payload | Shown as |
| --- | --- |
| `Map`, `List`, objects with `toJson()`, JSON text | Redacted, pretty-printed JSON |
| XML / HTML | Redacted, indented markup |
| Form-encoded | A key/value table |
| Multipart (`FormData`, `MultipartRequest`) | Field table and file metadata; file contents are never read |
| Protobuf / gRPC | Decoded with your decoder, otherwise `<protobuf, N bytes>` |
| Binary (`image/*`, `octet-stream`, …) | `<binary, N bytes>` |
| Streams | `<stream not captured>` |
| Anything else | `<TypeName>`; `toString()` is never called |

### Protocol Buffers

Netoscope cannot decode protobuf without your schema. It has no protobuf
dependency, so you supply the decoding:

```dart
final netoscope = Netoscope(
  config: NetworkLoggerConfig(
    payloadDecoders: [
      ProtobufPayloadDecoder(
        decode: (bytes, context) => switch (context.url?.path) {
          '/helloworld.Greeter/SayHello' =>
            context.direction == MessageDirection.outgoing
                ? HelloRequest.fromBuffer(bytes).toProto3Json()
                : HelloReply.fromBuffer(bytes).toProto3Json(),
          _ => null, // unknown message: shown as binary
        },
      ),
    ],
  ),
);
```

gRPC and gRPC-Web bodies are split into frames first, and `decode` receives
one message at a time. Compressed frames are reported, not decompressed.

### Custom formats

Implement `PayloadDecoder` for any other format. `PayloadFormat` is open, so
you can introduce your own:

```dart
class MsgPackDecoder implements PayloadDecoder {
  @override
  PayloadFormat get format => const PayloadFormat('msgpack', label: 'MessagePack');

  @override
  bool canDecode(PayloadContext context) =>
      context.contentType?.contains('msgpack') ?? false;

  @override
  Object? decode(Uint8List bytes, PayloadContext context) => deserialize(bytes);
}
```

A decoder runs only on complete payloads, before redaction. If it throws or
returns `null`, the next decoder or the built-in handling takes over.

## GraphQL

GraphQL needs no extra setup. Calls made through `dioInterceptor` or
`httpClient()` are recognized when the request carries a GraphQL document:
- A JSON body with a `query` that actually looks like GraphQL, so a search API
  posting `{"query": "shoes"}` is not misdetected.
- A batch of such bodies.
- A persisted query (`extensions.persistedQuery`).
- A `GET ?query=…`.
- An `application/graphql` body.
- The `operations` field of a multipart upload.

Netoscope captures:
- The operation name and type (query, mutation or subscription).
- The redacted document and variables.
- The persisted-query hash, when present.
- From the response: errors with their `path`, `extensions.code` and batch
  index, and whether `data` was present.

The HTTP outcome reflects the **transport** only. A `200 OK` with `errors` is
a transport success, flagged as `GQL ERR` in the inspector and exposed as
`entry.hasGraphQLErrors`. A response with both data and errors is reported as
partial.

```dart
final graphQL = entry.graphQL;               // GraphQLDetails?
graphQL?.operations.first.name;              // 'GetViewer'
graphQL?.errors.first.pathLabel;             // 'viewer.email'
graphQL?.isPartial;                          // data + errors
```

## Real-time protocols

Every recorder uses the same model. Connection events (opened, closed,
failed) share a `connectionId` with the connection's messages. When logging is
disabled or the URL is excluded, recorders do nothing and their `observe…`
methods return the original stream or sink.

### WebSocket

```dart
final channel = WebSocketChannel.connect(url);    // package:web_socket_channel
final socket = netoscope.webSocket(url, ignoreMessage: (m) => m == 'ping');

await channel.ready;
socket.connected(subprotocol: channel.protocol);

final messages = socket.observeIncoming(
  channel.stream,
  closeCode: () => channel.closeCode,
  closeReason: () => channel.closeReason,
);
final sink = socket.observeOutgoing(channel.sink);
// Use `messages` and `sink` instead of channel.stream / channel.sink.
```

How the observers behave:
- **Data:** what your code reads and writes is unchanged.
- **Single-subscription streams:** stay single-subscription. Pause, resume and
  cancel are forwarded to the source.
- **Broadcast streams:** returned as they are, and recorded once however many
  listeners you add.
- **Close codes:** `observeOutgoing` returns a plain `StreamSink`. To send a
  close code, call `channel.sink.close(code)` directly; the close is still
  recorded when the incoming stream ends.

### Server-Sent Events

`text/event-stream` responses from `netoscope.httpClient()` are recorded
automatically. With other clients, such as Dio with `ResponseType.stream`, wrap
the byte stream yourself:

```dart
final response = await dio.get<ResponseBody>(url,
    options: Options(responseType: ResponseType.stream));
final events = netoscope.serverSentEvents(Uri.parse(url))
  ..connected(statusCode: response.statusCode);
final bytes = events.observeBytes(response.data!.stream);
```

Each event records its type, ID, retry delay and redacted data. Event data is
bounded to 1 MiB per event.

### gRPC

gRPC-Web calls over Dio or `package:http` are recognized automatically. For
`package:grpc`, call the recorder from a `ClientInterceptor`. This recipe is
**not tested by Netoscope**, which has no `grpc` dependency; check it against
your `grpc` version:

```dart
class NetoscopeGrpcInterceptor extends ClientInterceptor {
  NetoscopeGrpcInterceptor(this.netoscope, this.host);

  final Netoscope netoscope;
  final Uri host;

  @override
  ResponseFuture<R> interceptUnary<Q, R>(ClientMethod<Q, R> method, Q request,
      CallOptions options, ClientUnaryInvoker<Q, R> invoker) {
    final call = netoscope.grpcCall(
      method.path,
      host: host,
      metadata: options.metadata,
      encodeMessage: (m) => m is GeneratedMessage ? m.toProto3Json() : m,
    )..sent(request);
    final response = invoker(method, request, options);
    response.then(
      (reply) => call
        ..received(reply)
        ..finish(),
      onError: (Object error) => error is GrpcError
          ? call.finish(statusCode: error.code, statusMessage: error.message)
          : call.fail(error),
    );
    return response;
  }
}
```

The handlers are attached to the same future your code receives. They do not
change its result or errors. For streaming calls, pass
`callType: GrpcCallType.serverStreaming` (or another streaming type) and call
`received` for each message.

### MQTT

```dart
final mqtt = netoscope.mqtt(Uri.parse('mqtts://broker.example.com'),
    clientId: 'app-1');
client.onConnected = mqtt.connected;
client.onDisconnected = mqtt.disconnected;
client.onSubscribed = (topic) => mqtt.subscribed(topic);
client.updates!.listen((messages) {
  for (final m in messages) {
    final payload = (m.payload as MqttPublishMessage).payload.message;
    mqtt.received(m.topic, payload);
  }
});
// After client.publishMessage(...):
mqtt.published(topic, payload, qos: 1);
```

### Other protocols

```dart
final printer = netoscope.connection(Uri.parse('tcp://printer.local:9100'),
    label: 'RAW')
  ..opened();
printer.message(MessageDirection.outgoing, jobBytes);
printer.closed();
```

## Webhooks

### Outbound deliveries from this app

A request counts as a webhook delivery when its URL matches
`WebhookConfig.endpoints`, or when a Dio request carries a `WebhookAttempt`:

```dart
final netoscope = Netoscope(
  config: const NetworkLoggerConfig(
    webhooks: WebhookConfig(endpoints: ['hooks.partner.example'], maxAttempts: 5),
  ),
);

dio.post(url, data: payload, options: Options(extra: {
  Netoscope.webhookKey: const WebhookAttempt(
    eventType: 'order.created', deliveryId: 'dlv_1', attempt: 2, maxAttempts: 5),
}));
```

Each attempt records:
- **Outcome:** `delivered` (2xx); `retryable` (timeout, connection error, 408,
  425, 429 or 5xx); `exhausted` (retryable, but on the last attempt);
  `rejected` (other 4xx).
- **Delivery details:** event type, delivery ID, attempt number and the
  delivery error.
- **Signature algorithm only:** for example `sha256` from
  `X-Hub-Signature-256: sha256=…`.

Delivery IDs, event types and attempt numbers can also come from common
headers. `WebhookConfig` lists them, and you can change the names.

**Signature headers are always fully redacted.** Only known algorithm names
can be extracted, so a signature value never reaches the logs. Netoscope never
sees signing keys.

### Deliveries made by your backend

A Flutter interceptor **cannot** observe webhooks your servers send or
receive. If your backend keeps delivery logs, fetch them through your own API
and import them. They are redacted like captured traffic:

```dart
netoscope.importWebhookDeliveries([
  for (final log in await myApi.webhookDeliveryLogs())
    WebhookDeliveryRecord(
      endpoint: Uri.parse(log.url),
      timestamp: log.sentAt,
      eventType: log.event,
      attempt: log.attempt,
      maxAttempts: log.maxAttempts,
      statusCode: log.responseStatus,
      duration: log.duration,
      error: log.error,
      requestHeaders: log.headers,
      requestBody: log.payload,
    ),
]);
```

## Event model

Every recorded event is a `NetworkLogEntry`. HTTP calls look exactly as they
did in 0.1.0. The newer fields have defaults:

| Field | Meaning |
| --- | --- |
| `protocol` | `http`, `webSocket`, `sse`, `grpc`, `mqtt`, `other` |
| `kind` | `exchange` (request/response), `connection` (lifecycle) or `message` |
| `direction` | `outgoing` / `incoming` for messages |
| `lifecycle` | `opened` / `closed` / `failed` for connection events |
| `connectionId` | Groups a connection's events |
| `details` | Typed `ProtocolDetails`: `GraphQLDetails`, `WebhookDetails`, `GrpcDetails`, `SseDetails`, `WebSocketDetails`, `MqttDetails`, `TransferDetails` |
| `metadata` | Free-form, redacted strings (for example message counts on close) |
| `requestBody` / `responseBody` | `NetworkLogBody` with `kind`, `format` (`PayloadFormat`), `contentType`, `content`, `isTruncated` |

```dart
entry.detail<SseDetails>()?.eventType;
entry.webhook?.outcome;
entry.messageBody;              // the payload of a message, either direction
entry.outcome;                  // success, httpError, failure, cancelled
```

`ProtocolDetails` is an open class, so custom recorders can attach their own
details.

## Architecture

Netoscope follows a layered design with Clean Architecture dependency rules.
Dependencies point inwards only.

```
lib/
  netoscope.dart                 public exports
  src/
    core/                        entities, contracts (store, sink, PayloadDecoder), use cases
    config/                      NetworkLoggerConfig
    security/                    redaction, payload capture pipeline, format detection, protobuf decoder
    protocols/                   pure-Dart protocol parsing: GraphQL, gRPC framing, SSE, webhooks
    data/                        in-memory store, console sink, JSON export
    adapters/                    Dio interceptor, package:http client, real-time recorders, webhook import
    network_inspector.dart       Netoscope facade (composition root)
    ui/                          optional Flutter inspector, filters, payload viewers
```

- **`core`** has no Dio, `http` or Flutter dependency, and no protocol
  library dependency.
- **`protocols` and `security`** are pure Dart and depend only on `core`.
- **`adapters`** translate client types and recorder calls into entries
  through the security and protocol layers.
- **The facade** wires everything with constructor injection. There are no
  singletons or global state.
- **`ui`** depends only on the facade's public API and core entities. The
  facade does not import the UI.

## Example

[`example/`](example) is a runnable app with an offline demo backend, so no
network access or credentials are needed:

```sh
cd example
flutter run
```

It demonstrates:
- **REST calls:** GET and POST, redaction, a 404, a slow call, a timeout, a
  cancellation and an excluded endpoint.
- **Protocols:** a GraphQL query with partial errors, a Server-Sent Events
  stream, a simulated WebSocket session and a webhook delivery that gets a 503.
- **Tooling:** `package:http` and the inspector.

### Screenshots

_Screenshots of the inspector will be added before the first stable
release._

## Testing

```sh
flutter test              # package tests
cd example && flutter test
```

The tests use fake Dio adapters, `package:http`'s `MockClient`, in-memory
streams and hand-built protocol fixtures. They never touch the network.

## Limitations

- **Duration** is measured from when Netoscope sees the request:
  - Dio: when the interceptor runs. With `ResponseType.stream`, timing stops
    when the headers arrive.
  - `package:http`: when the body has been fully read.
  - Closed connections: the duration is the connection's lifetime.
- **`package:http`:**
  - A call is recorded once its response stream completes, fails or is
    cancelled, so a response that is never read is never recorded.
  - Event streams are the exception: they are recorded as they arrive.
  - The returned response is a plain `StreamedResponse`, so subclasses such as
    `IOStreamedResponse` (with `detachSocket`) are not preserved.
  - Timeouts applied outside the client, such as
    `client.get(url).timeout(...)`, are not visible.
- **Dio:**
  - If a later interceptor *replaces* `RequestOptions` (`copyWith`), that
    call's duration is unknown.
  - SSE over Dio needs the manual `serverSentEvents` recorder.
  - Decoded JSON without `Content-Length` has no size.
- **`dart:io` capture** only wraps `HttpClient`s created after
  `captureDartIo()`, and is replaced if other code installs `HttpOverrides`
  later.
- **Recorder-based protocols** (WebSocket, native gRPC, MQTT, custom) see only
  what you route through the recorder. Netoscope does not hook sockets.
- **GraphQL:**
  - Responses larger than 1 MiB are not parsed for errors.
  - Detection depends on the request body being available. Requests sent as
    `http.StreamedRequest`, or as Dio streams, are not recognized.
- **gRPC:** native gRPC over plain HTTP clients is not supported (no trailer
  access), and compressed and `grpc-web-text` messages are not decoded.
- **History:** entries are recorded on completion (exchanges) or when they
  happen (connection events and messages). In-flight HTTP calls are not shown,
  and history is lost when the app restarts.
- **Redaction** is key- and pattern-based. Secrets under innocuous keys or
  inside free text may not be detected.

## Security considerations

- Network logs can contain personal data and credentials even after
  redaction. Treat exports and screenshots accordingly.
- Logging is disabled in release builds unless you pass `enabled: true`.
  Only do that deliberately, for example in internal QA builds.
- Netoscope sends nothing anywhere. Entries go only to the in-memory store,
  the console and any sinks you add.
- Webhook signature values and signing keys are never recorded.
- Netoscope is not a substitute for production observability, audit logging
  or data-protection controls.

## Contributing

Issues and pull requests are welcome. Before submitting:

```sh
dart format .
flutter analyze
flutter test
```

Keep `core`, `protocols` and `security` free of Flutter and client-library
imports, add tests for new behavior and document public APIs.

## License

[MIT](LICENSE)
