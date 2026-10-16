# netoscope_integration_tests

Not published. These tests verify Netoscope with real third-party HTTP
clients against a local loopback server:
- **Retrofit:** a code-generated API on Dio.
- **Chopper:** `ChopperClient` on `netoscope.httpClient()`.
- **`gql_http_link`:** the HTTP link used by `graphql`, `graphql_flutter`
  and `ferry`.
- **`dart:io` capture together with the above:** checks that no call is
  recorded twice.

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regenerate Retrofit code
flutter test
```
