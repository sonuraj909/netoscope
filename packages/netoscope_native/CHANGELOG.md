## Unreleased

- iOS: Swift Package Manager support. The plugin ships a `Package.swift`
  alongside its podspec, so it builds with SPM-enabled Flutter projects
  (Flutter 3.50 no longer warns that it lacks SPM support) and still builds
  with CocoaPods. Sources moved to `ios/netoscope_native/Sources/`.
- iOS: the privacy manifest is now bundled, through both SPM and CocoaPods.

## 0.1.0

- Android: `NetoscopeInterceptor` for OkHttp. It reads bodies with
  `peekBody`, records textual bodies only, and keeps up to 50 calls until
  Dart attaches.
- iOS: `NetoscopeURLProtocol` for `URLSession`/`NSURLConnection`, with
  opt-in capture of all `default`/`ephemeral` sessions and `enable(on:)`.
- Dart: `NetoscopeNative.attach`/`detach`. Calls are recorded through
  `Netoscope.recordExternalCall`, with `source` set to `android` or `ios`.
