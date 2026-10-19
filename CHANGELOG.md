## 0.2.3

- `NetworkLoggerConfig.inspectorThemeMode` (`system`, `light`, `dark`):
  force the inspector's theme instead of following the app's brightness, for
  example a dark inspector in a light-only app. Applies to every inspector
  screen. The default, `system`, keeps the previous behavior.
- Theme switch in the inspector's settings panel (System / Light / Dark), and
  `Netoscope.setInspectorThemeMode` to change it from code. Open inspector
  screens update immediately. `NetoscopeSettings` gains `themeMode`.

## 0.2.2

- README: a quick start and a guide for switching from other network loggers.
- Clearer package description.

## 0.2.1

- Adds screenshots to the pub.dev listing and the README.

## 0.2.0

Multi-protocol inspection. Existing HTTP integrations and APIs keep working
unchanged.

- **Responsive inspector:** verified from 320 pt phones to 1440 px desktops,
  in landscape, at 1.3× and 2× text and right-to-left. On narrow toolbars,
  Timeline and Statistics move into the More menu. Detail and statistics
  content stays within a readable 960 px column on wide screens. List rows,
  JSON tree keys and the timeline adapt to large text instead of overflowing.
- **Event model:** `NetworkLogEntry` gains `protocol`, `kind`, `direction`,
  `lifecycle`, `connectionId`, typed `details` (`ProtocolDetails`) and
  `metadata`, all optional with HTTP defaults. `NetworkLogBody` gains an open
  `PayloadFormat` and `contentType`.
- **Payload pipeline:**
  - Content-type-first format detection with sniffing (JSON, XML, HTML, form,
    multipart, protobuf, text, binary).
  - XML/HTML-aware redaction.
  - A pluggable `PayloadDecoder` contract and `ProtobufPayloadDecoder`, which
    understands gRPC framing.
- **GraphQL over HTTP:**
  - Operations, types, redacted documents and variables, persisted queries,
    batches and multipart uploads.
  - Errors with paths and codes, and partial data.
  - Transport outcome is kept separate from GraphQL execution errors.
- **Server-Sent Events:** recorded automatically by `httpClient()`, live and
  without buffering. `SseRecorder` covers other clients.
- **Real-time recorders:** `WebSocketRecorder` (including GraphQL over
  WebSocket), `MqttRecorder`, `GrpcCallRecorder` and a generic
  `ConnectionRecorder`. None of them add dependencies.
- **gRPC-Web** recognized over Dio and `package:http`.
- **Webhooks:**
  - Outbound delivery attempts with outcome and retryability.
  - Signatures are reduced to their algorithm.
  - `importWebhookDeliveries` imports backend delivery logs.
- **Dio** upload/download progress is recorded for requests that report it.
- **Inspector:**
  - Protocol-aware rows and a filters sheet: protocol, time range, GraphQL,
    message direction, SSE event type and payload format.
  - Search across operations, events and topics.
  - A GraphQL tab and connection event views.
  - Custom `PayloadViewer`s.
  - Background formatting and lazy rendering for large bodies.
- **Deep inspection:**
  - **Search syntax:** `method:`, `status:` (ranges, classes, outcomes),
    `host:`, `path:`, `duration:`, `size:`, `protocol:`, `tag:`, `is:`, `op:`,
    `header:`, `body:` and more, with negation and alternatives, plus an
    in-app cheat sheet.
  - **Call tagging:** `tagged()` (zone-scoped, across all clients),
    `addTag`/`removeTag`/`clearTags`, and per-request Dio tags.
    `NetworkLogEntry.tags`.
  - **Duplicate and N+1 detection:** `TrafficAnalyzer`, `analyzeTraffic()`,
    row badges, explanations, and group views.
  - **Statistics dashboard:** `TrafficStatistics` and `statistics()`.
  - **Gantt timeline:** zoom, fit and tap to open.
- **Persistence and export:**
  - `NetworkLogEntry.fromJson` and `fromJson` for every entity.
  - `NetworkLogPersistence`, `FileNetworkLogPersistence` and
    `PersistentNetworkLogStore`.
  - HAR 1.2 export (`exportHar()`), and an `exportHandler` hook for sharing.
- **Native capture:**
  - `recordExternalCall` and `ExternalNetworkCall`.
  - The new `netoscope_native` plugin (OkHttp interceptor and `URLSession`
    capture).
- **`dart:io` capture:**
  - `captureDartIo()`, `stopCapturingDartIo()` and `isCapturingDartIo` record
    `HttpClient` calls (including `Image.network` and SDKs) through a chained
    `HttpOverrides`.
  - Calls already recorded by the Dio or `http` hooks are not doubled.
  - Web builds are unaffected (conditional import).
- **Client compatibility:** Retrofit, Chopper and `gql_http_link` (used by
  `graphql`, `graphql_flutter` and `ferry`) are verified by integration tests
  in `packages/netoscope_integration_tests`.
- **Runtime switches:**
  - `setLoggingEnabled`, `setFloatingButtonEnabled`, `setNotificationEnabled`
    and `updateSettings`, plus `settings`, `settingsChanges` and `isRecording`.
  - An inspector settings panel and a "Recording paused" banner.
  - The switches are ignored when logging is disabled for the build.
- **Activity notification:**
  - The `NetworkActivityNotifier` contract, with `Netoscope(notifier:)`,
    `attachNotifier` and a throttled `NetworkActivitySummary`.
  - The companion package `netoscope_notifications` implements it with
    `flutter_local_notifications`; tapping the notification opens the
    inspector.
- **Inspector helpers:** `openInspectorOn(navigator)` opens without a
  `BuildContext`, and `isInspectorOpen` reports whether one is showing. The
  floating button hides while the inspector is open.
- **Copy as cURL:** from the detail screen or a long-press on a row. The
  command is built from redacted data and says when values are masked.
- **Inspector redesign:**
  - Colored method and status pills, an outcome accent bar on each row and a
    summary strip.
  - A header card with stats and copy actions, and card-style sections.
- **Payload views:** syntax-highlighted JSON, XML/HTML, GraphQL and forms
  with line numbers and wrap, a collapsible JSON tree, and highlighted
  redacted values.
- **Console:** verbose output is framed and pretty-printed, with optional
  ANSI colors (`consoleColors`).
- **Config:** `consoleColors`, `payloadDecoders`, `detectGraphQL`, `webhooks`,
  `captureTransferProgress` and `captureRealtimeMessages`.
- **Behavior changes:**
  - `signature` is now a sensitive-key fragment.
  - The inspector's "Failed" filter now means a failed or cancelled outcome.
    For HTTP calls this is unchanged.
  - Exported body JSON includes `format` and `contentType`.

## 0.1.0

Initial release.

- `Netoscope` facade with `dioInterceptor`, `httpClient()`, `logs`,
  `logChanges`, `clearLogs()`, `exportJson()` and `openInspector()`.
- Dio interceptor: captures successes, HTTP errors, timeouts, connection
  failures and cancellations without altering requests, responses or errors.
- `package:http` client wrapper that observes response streams without
  consuming them.
- Redaction of credentials, tokens, passwords, OTPs, cookies, API keys,
  nested JSON fields and URL query parameters, with configurable extra keys.
- Safe capture of JSON, text, form, multipart, binary and streamed bodies,
  with truncation.
- Bounded in-memory history with a change stream.
- Console output via `dart:developer` at `none`, `summary` or `verbose` level.
- Optional inspector with search, status/method/slow filters, detail view,
  copy and JSON export, plus `NetworkInspectorButton` and
  `NetworkInspectorOverlay`.
- Logging disabled by default in release builds.
