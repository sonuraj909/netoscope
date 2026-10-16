# Netoscope example

A small Flutter app that shows how to use Netoscope with Dio and
`package:http`.

All requests go to an offline demo backend (`lib/demo_backend.dart`), so the
app works without network access or credentials. To log real traffic, remove
the `httpClientAdapter` and `demoHttpClient()` lines in `lib/main.dart`.

## Run

```sh
flutter pub get
flutter run          # any supported device, e.g. -d chrome
flutter test
```

## What to try

1. Tap **POST /auth/login**, open the inspector (floating button or the app
   bar icon), open the call and check that the password, email,
   `Authorization` header, tokens and `set-cookie` are masked.
2. Tap **GET /orders/42**, **GET /flaky** and **GET /long-poll** to see a
   404, a timeout and a cancellation.
3. Tap **GET /reports/annual**, then use the **Slow** filter.
4. Tap **GET /health** and note that it is excluded from the logs.
5. Search, filter by status or method, copy a call as JSON, export everything,
   and clear the history.

## Native capture test

`integration_test/native_capture_test.dart` runs real native requests
(OkHttp on Android, `URLSession` on iOS) and checks that they're captured and
redacted:

```sh
flutter test integration_test -d <device-id>
```
