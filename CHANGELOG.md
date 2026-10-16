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
