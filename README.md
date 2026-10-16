# Netoscope

Debug-time network logging and inspection for Flutter.

Netoscope records the HTTP calls your app makes through **Dio** or
**`package:http`**, redacts secrets before anything is printed or stored,
keeps a bounded history in memory and, if you want it, shows that history in
an in-app inspector.

> **Netoscope is a debugging aid, not a production observability tool.**
> Logging is off in release builds by default. See
> [Security considerations](#security-considerations).

## Features

- Dio interceptor and `package:http` client wrapper, both feeding one history
- Method, URL, query parameters, headers, bodies, status, duration, sizes and errors
- Distinguishes successes, HTTP errors, timeouts, connection failures and cancellations
- Redaction of authorization headers, cookies, tokens, passwords, OTPs, API
  keys, nested JSON fields and URL query parameters, plus your own keys
- Safe handling of JSON, text, form, multipart, binary and streamed bodies,
  with truncation
- Bounded in-memory history, newest first, with a change stream
- URL exclusions and a per-request opt-out
- Console output through `dart:developer` (no `print`)
- JSON export of the whole history or a single call
- Optional inspector with search, method/status/slow filters, details and copy
- Optional floating button to open the inspector from anywhere

## Requirements

- Dart `>=3.5.0 <4.0.0`
- Flutter `>=3.24.0`
- Dio `^5.4.0` and/or `package:http` `^1.5.0` (both are dependencies of
  Netoscope; use whichever your app needs)

## Installation

```sh
flutter pub add netoscope
```

```dart
import 'package:netoscope/netoscope.dart';
```

## Quick start

Create **one** `Netoscope` for the app and attach it to your clients.

### Dio

```dart
final netoscope = Netoscope();

final dio = Dio()
  // Add Netoscope last so it sees headers added by other interceptors.
  ..interceptors.add(netoscope.dioInterceptor);
```

The interceptor only observes: requests, responses and errors are passed on
unchanged, and `DioException`s still reach your code.

To keep a single request out of the logs:

```dart
dio.get('/metrics', options: Options(extra: {Netoscope.skipLoggingKey: true}));
```

### package:http

```dart
final netoscope = Netoscope();

final client = netoscope.httpClient();               // wraps http.Client()
final custom = netoscope.httpClient(myRetryClient);  // or wraps your client

final response = await client.get(Uri.parse('https://api.example.com/users'));
```

The wrapper observes the response body as you read it, so nothing is consumed
on your behalf. See [Limitations](#limitations).

### Console-only setup

The inspector is optional. Without it, Netoscope simply writes one line per
call to the debug console:

```dart
final netoscope = Netoscope(
  config: const NetworkLoggerConfig(
    showInspector: false,
    consoleLogLevel: ConsoleLogLevel.summary, // or .verbose for headers/bodies
  ),
);
```

```
POST https://api.example.com/auth/login → 200 (243 ms)
GET https://api.example.com/reports → 200 (3412 ms) [SLOW]
GET https://api.example.com/flaky → FAILURE (402 ms)
  error: timeout: The request took longer than the receive timeout.
```

Output uses `dart:developer`'s `log`, which shows in IDE debug consoles and
DevTools. To use another output, such as `debugPrint`, turn the built-in sink
off and add your own:

```dart
final netoscope = Netoscope(
  config: const NetworkLoggerConfig(consoleLogLevel: ConsoleLogLevel.none),
  sinks: [ConsoleNetworkLogSink(output: debugPrint)],
);
```

### Inspector setup

Open it from anywhere you have a `BuildContext` under your `Navigator`:

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

`NetworkInspectorButton` is also available on its own, and `NetworkInspector`
is a regular widget you can embed. All of them render nothing (or just
`child`) when the inspector is unavailable, so they can stay in release builds.

The inspector provides:

- a list of calls with method, path, host, time, status and duration
- search by URL or endpoint
- filters by status group (2xx, 3xx, 4xx, 5xx, failed), method and slow calls
- a detail view with general info, query parameters, headers, pretty-printed
  JSON bodies and error details
- copy of a single call, or the whole history, as JSON
- clearing the history

### Reading history in code

```dart
final List<NetworkLogEntry> logs = netoscope.logs;        // newest first
netoscope.logChanges.listen((logs) { /* … */ });          // on every change
final String json = netoscope.exportJson();               // redacted JSON
netoscope.clearLogs();
```

## Configuration

| Option | Default | Description |
| --- | --- | --- |
| `enabled` | `null` | `null` logs in debug/profile and **not** in release. `true`/`false` force it. |
| `consoleLogLevel` | `summary` | `none`, `summary` (one line per call) or `verbose` (adds headers and bodies). |
| `showInspector` | `true` | Whether the inspector, button and overlay are available. |
| `maxHistorySize` | `100` | Calls kept in memory; the oldest are evicted. |
| `maxBodySize` | `32768` | Characters kept per body; longer bodies are truncated. `0` keeps only the kind. |
| `captureRequestBody` | `true` | Capture request bodies. |
| `captureResponseBody` | `true` | Capture response bodies. |
| `captureHeaders` | `true` | Capture request and response headers. |
| `excludedUrls` | `[]` | `String` (substring) or `RegExp` patterns; matching calls are not logged. |
| `slowRequestThreshold` | `3 s` | Calls at least this long are flagged as slow. |
| `sensitiveKeys` | `{}` | Extra keys to redact, in addition to the built-in list. |
| `redactionMask` | `'***'` | Replacement for redacted values. |

Worst-case memory is roughly
`maxHistorySize × 2 bodies × maxBodySize` characters (about 13 MB with the
defaults). Lower either value for memory-constrained devices.

## Redaction

Redaction runs inside the adapters, **before** an entry is printed, stored,
shown or exported. It applies to header names, query parameter names and map
keys at any depth in JSON bodies. Matching ignores case, `-`, `_`, `.` and
spaces.

A key is redacted when it

- **contains** `authorization`, `cookie`, `password`, `passwd`, `passphrase`,
  `secret`, `token`, `apikey`, `credential`, `session` or `privatekey`
  (so `Set-Cookie`, `X-API-Key`, `access_token`, `refreshToken`, `newPassword`
  all match), or
- **equals** `otp`, `otpcode`, `pin`, `pwd`, `cvv`, `cvc`, `ssn`, `auth`,
  `jwt`, `signature` or `sig`, or
- equals one of your `sensitiveKeys`.

URL credentials (`https://user:pass@host`) and `Bearer`/`Basic` credentials in
free text and error messages are masked too.

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

How bodies are captured:

| Payload | Captured as |
| --- | --- |
| `Map`, `List`, objects with `toJson()` | Redacted JSON |
| JSON strings or bytes | Parsed, redacted, re-encoded |
| Form-encoded or plain text | Text, with `key=value` and `"key": value` patterns redacted |
| Multipart (`FormData`, `MultipartRequest`) | Field names/values (redacted) and file metadata; never file contents |
| Binary (`Uint8List`, `image/*`, `application/octet-stream`, …) | `<binary, N bytes>` |
| Streams (`ResponseType.stream`, `StreamedRequest`) | `<stream not captured>`; never listened to |
| Anything else | `<TypeName>`; `toString()` is never called |

Bodies larger than 1 MiB are not parsed. They are redacted by pattern and
truncated.

## Excluding endpoints

```dart
final netoscope = Netoscope(
  config: NetworkLoggerConfig(
    excludedUrls: [
      '/health',                          // substring
      RegExp(r'^https://analytics\.'),    // regular expression
    ],
  ),
);
```

Exclusions are checked against the full URL, including the query string,
before redaction.

## Architecture

Netoscope follows a layered design with Clean Architecture dependency rules.
Dependencies point inwards only.

```
lib/
  netoscope.dart                 public exports
  src/
    core/                        entities, contracts, use cases (pure Dart)
    config/                      NetworkLoggerConfig
    security/                    LogRedactor, BodyCapture (redaction, truncation)
    data/                        InMemoryNetworkLogStore, console sink, JSON export
    adapters/                    Dio interceptor, package:http client, shared capture policy
    network_inspector.dart       Netoscope facade (composition root)
    ui/                          optional Flutter inspector
```

- `core` imports nothing from the package except other `core` files. It has no
  Dio, `http` or Flutter dependency.
- `data` implements the core contracts.
- `security` turns raw payloads into safe values for the core entities.
- `adapters` translate Dio and `http` types into `NetworkLogEntry` objects through
  the security layer.
- The `Netoscope` facade wires these together with constructor injection.
  There are no singletons or global state.
- `ui` depends only on the facade's public API. The facade does not import the UI;
  `openInspector` is an extension provided by the UI layer.

## Example

[`example/`](example) is a runnable app that uses an offline demo backend, so
no network access or credentials are needed:

```sh
cd example
flutter run
```

It demonstrates GET/POST requests, redaction, a 404, a slow call, a timeout,
a cancelled call, an excluded endpoint, `package:http`, and the inspector.

### Screenshots

_Screenshots of the inspector list and detail views will be added before the
first stable release._

## Testing

```sh
flutter test              # package tests
cd example && flutter test
```

The test suite uses fake Dio adapters and `package:http`'s `MockClient`; it
never touches the network.

## Limitations

- **Duration** is measured from the moment Netoscope sees the request. For Dio
  that is when the interceptor runs; for `ResponseType.stream` it stops when
  headers arrive. For `package:http` it stops when the response body has been
  fully read.
- **`package:http`**: a call is recorded once its response stream completes,
  fails or is cancelled. A response that is never read is never recorded.
  The returned response is a plain `StreamedResponse`, so client-specific
  subclasses such as `IOStreamedResponse` (with `detachSocket`) are not
  preserved. Timeouts applied *outside* the client, such as
  `client.get(url).timeout(...)`, are not visible to the wrapper.
- **Dio**: if another interceptor *replaces* `RequestOptions` (via
  `copyWith`) after Netoscope, the duration for that call is unknown. Response
  sizes come from `Content-Length`, or from raw strings and bytes; decoded JSON
  without `Content-Length` has no size.
- Entries are recorded on completion. In-flight calls are not shown.
- History lives in memory and is lost when the app restarts.
- Redaction is key-based. Secrets stored under innocuous keys, or embedded
  in free text, are not detected. Add such keys to `sensitiveKeys`, or disable
  body capture for those endpoints.

## Security considerations

- Network logs can contain personal data and credentials even after
  redaction. Treat exports and screenshots accordingly.
- Logging is disabled in release builds unless you pass `enabled: true`.
  Only do that deliberately, for example in internal QA builds.
- Netoscope does not send data anywhere. Entries reach only the in-memory
  store, the console and any sinks you add.
- The package is not a substitute for production observability, audit
  logging or data-protection controls.

## Contributing

Issues and pull requests are welcome. Before submitting:

```sh
dart format .
flutter analyze
flutter test
```

Keep `core` free of Flutter and HTTP-client imports, add tests for new
behavior and document public APIs.

## License

[MIT](LICENSE)
