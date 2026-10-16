## 0.1.0

- Android: `NetoscopeInterceptor` for OkHttp. It reads bodies with
  `peekBody`, records textual bodies only, and keeps up to 50 calls until
  Dart attaches.
- iOS: `NetoscopeURLProtocol` for `URLSession`/`NSURLConnection`, with
  opt-in capture of all `default`/`ephemeral` sessions and `enable(on:)`.
- Dart: `NetoscopeNative.attach`/`detach`. Calls are recorded through
  `Netoscope.recordExternalCall`, with `source` set to `android` or `ios`.
