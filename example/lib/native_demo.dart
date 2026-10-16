import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Demos that run outside Dart's HTTP clients: native OkHttp/URLSession
/// calls (captured by netoscope_native) and raw dart:io HttpClient calls
/// (captured by captureDartIo).
class NativeDemo {
  const NativeDemo(this.label, this.description, this.icon, this.run);

  final String label;
  final String description;
  final IconData icon;
  final Future<void> Function() run;

  static const _channel = MethodChannel('netoscope_example/native');

  static String get _nativeClient =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'URLSession' : 'OkHttp';

  static List<NativeDemo> all(Uri server) => [
    NativeDemo(
      'Native GET ($_nativeClient)',
      'Made by ${defaultTargetPlatform == TargetPlatform.iOS ? 'Swift' : 'Kotlin'} '
          'code; the session token is masked.',
      Icons.phone_iphone,
      () => _channel.invokeMethod<String>('request', {
        'url': server.replace(path: '/native/profile').toString(),
      }),
    ),
    NativeDemo(
      'Native POST (redacted)',
      'A native login: password and Authorization are masked.',
      Icons.lock_person_outlined,
      () => _channel.invokeMethod<String>('request', {
        'url': server.replace(path: '/native/login').toString(),
        'body': jsonEncode({'username': 'grace', 'password': 'cobol'}),
      }),
    ),
    if (defaultTargetPlatform == TargetPlatform.iOS)
      NativeDemo(
        'URLSession (custom session)',
        'A session from URLSessionConfiguration.default, also captured.',
        Icons.settings_ethernet,
        () => _channel.invokeMethod<String>('request', {
          'url': server.replace(path: '/native/profile').toString(),
          'session': 'custom',
        }),
      ),
    NativeDemo(
      'dart:io HttpClient GET',
      'A plain HttpClient call, captured by captureDartIo().',
      Icons.terminal,
      // IOClient uses dart:io HttpClient underneath, bypassing the
      // Netoscope http wrapper, so only the dart:io capture sees it.
      () async {
        final client = http.Client();
        try {
          await client.get(server.replace(path: '/native/profile'));
        } finally {
          client.close();
        }
      },
    ),
  ];
}
