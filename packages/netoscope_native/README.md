# netoscope_native

Native network capture for [Netoscope](../../README.md). It records HTTP
calls made by **Android (OkHttp)** and **iOS (URLSession)** code, such as
your own platform code or native SDKs, into the same redacted history as
your Dart traffic.

Calls are sent to Dart and recorded with `Netoscope.recordExternalCall`:
- They're redacted, truncated and inspected (GraphQL, gRPC-Web, webhooks)
  exactly like Dart calls.
- Their metadata `source` is `android` or `ios`, so `source:ios` finds them
  in the inspector.

## Setup

```dart
final netoscope = Netoscope();
await NetoscopeNative.attach(netoscope);                              // iOS: URLSession.shared
await NetoscopeNative.attach(netoscope, captureAllUrlSessions: true); // iOS: every default/ephemeral session too
```

`attach` returns `false` and does nothing when Netoscope is disabled for the
build (the release default), on other platforms, or without the plugin.
`NetoscopeNative.detach()` stops forwarding.

### Android: OkHttp

Add the interceptor to the OkHttp clients your native code uses:

```kotlin
import dev.netoscope.netoscope_native.NetoscopeInterceptor

val client = OkHttpClient.Builder()
    .addInterceptor(NetoscopeInterceptor())
    .build()
```

The plugin compiles against OkHttp 4 but doesn't bundle it (`compileOnly`),
so it uses your app's OkHttp. The interceptor only observes:
- Requests and responses are passed on unchanged.
- Response bodies are read with `peekBody`, so your code still reads the full
  body.
- Only textual bodies are recorded, up to 1 MiB by default.
- Streaming (`text/event-stream`), media, one-shot and duplex bodies aren't
  read.

Calls captured before Dart attaches are kept (up to 50) and delivered on
attach.

### iOS: URLSession

`attach` registers `NetoscopeURLProtocol`, which captures `URLSession.shared`
and `NSURLConnection`.

Sessions with their own configuration need one of two things:
- `captureAllUrlSessions: true`. It adds the protocol to every
  `URLSessionConfiguration.default` and `.ephemeral` created afterwards, by
  swizzling those two factories.
- An explicit call in Swift, before creating the session:
  ```swift
  let configuration = URLSessionConfiguration.default
  NetoscopeURLProtocol.enable(on: configuration)
  let session = URLSession(configuration: configuration)
  ```

Each request is re-issued unchanged. Responses, data, redirects and
authentication challenges are relayed to the original client, and up to
1 MiB of each body is recorded.

## Limitations

- **Android:**
  - Only OkHttp clients you add the interceptor to are captured.
  - `HttpURLConnection`, Cronet and SDK-internal clients that don't accept an
    interceptor aren't captured.
- **iOS:**
  - Background sessions (`URLSessionConfiguration.background`) and
    `WKWebView` traffic aren't captured. Neither are sessions created before
    `attach` that don't include the protocol.
  - Each captured request runs on a separate internal session, so
    session-specific settings of the original session (such as custom
    delegates' certificate pinning) don't apply to the re-issued request.
    Use `enable(on:)` selectively if that matters.
- **Double capture:** don't combine native capture with a Dart wrapper
  around the same traffic. For example, `cupertino_http` wrapped with
  `netoscope.httpClient()` *and* captured natively would be recorded twice.
- **Debug only:** like Netoscope itself. Raw values cross the platform
  channel in-process before they're redacted in Dart.

## Verified

The example app's integration test (`example/integration_test`) runs real
native requests on the Android emulator (OkHttp) and the iOS simulator
(`URLSession.shared` and a custom session). It checks capture, `source`
labelling, redaction of `Authorization` headers, JSON passwords and tokens,
and that a parallel `dart:io` call is recorded once.

## License

MIT
