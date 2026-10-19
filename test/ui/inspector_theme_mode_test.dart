import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope/netoscope.dart';

import 'package:netoscope/src/ui/theme/inspector_theme.dart';
import 'package:netoscope/src/ui/widgets/settings_sheet.dart';

import '../support/fixtures.dart';

void main() {
  Netoscope netoscopeWith(InspectorThemeMode mode) => Netoscope(
        store: InMemoryNetworkLogStore()
          ..add(makeEntry(id: 'login', url: 'https://api.dev/login')),
        config: NetworkLoggerConfig(
          consoleLogLevel: ConsoleLogLevel.none,
          inspectorThemeMode: mode,
        ),
      );

  Future<void> pumpInspector(
    WidgetTester tester,
    Netoscope netoscope, {
    required Brightness hostBrightness,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: hostBrightness),
        home: NetworkInspector(netoscope: netoscope),
      ),
    );
  }

  Brightness brightnessAt(WidgetTester tester, Finder finder) =>
      Theme.of(tester.element(finder)).brightness;

  testWidgets('system follows the host brightness', (tester) async {
    await pumpInspector(
      tester,
      netoscopeWith(InspectorThemeMode.system),
      hostBrightness: Brightness.dark,
    );

    expect(brightnessAt(tester, find.text('/login')), Brightness.dark);
  });

  testWidgets('dark is used in a light-only app, on every screen',
      (tester) async {
    await pumpInspector(
      tester,
      netoscopeWith(InspectorThemeMode.dark),
      hostBrightness: Brightness.light,
    );

    expect(brightnessAt(tester, find.text('/login')), Brightness.dark);

    // Detail screens are pushed as separate routes on the host navigator and
    // must keep the forced theme too.
    await tester.tap(find.text('/login'));
    await tester.pumpAndSettle();
    expect(
      brightnessAt(tester, find.text('https://api.dev/login')),
      Brightness.dark,
    );
  });

  testWidgets('light is used in a dark app', (tester) async {
    await pumpInspector(
      tester,
      netoscopeWith(InspectorThemeMode.light),
      hostBrightness: Brightness.dark,
    );

    expect(brightnessAt(tester, find.text('/login')), Brightness.light);
  });

  testWidgets('config sets the initial runtime setting', (tester) async {
    final netoscope = netoscopeWith(InspectorThemeMode.dark);
    expect(netoscope.settings.themeMode, InspectorThemeMode.dark);
  });

  testWidgets('switching at runtime updates every open screen', (tester) async {
    final netoscope = netoscopeWith(InspectorThemeMode.system);
    await pumpInspector(tester, netoscope, hostBrightness: Brightness.light);
    await tester.tap(find.text('/login'));
    await tester.pumpAndSettle();
    final detail = find.text('https://api.dev/login');
    expect(brightnessAt(tester, detail), Brightness.light);

    netoscope.setInspectorThemeMode(InspectorThemeMode.dark);
    await tester.pumpAndSettle();
    expect(brightnessAt(tester, detail), Brightness.dark);

    netoscope.setInspectorThemeMode(InspectorThemeMode.system);
    await tester.pumpAndSettle();
    expect(brightnessAt(tester, detail), Brightness.light);
  });

  testWidgets('the settings sheet switches the theme', (tester) async {
    final netoscope = netoscopeWith(InspectorThemeMode.system);
    await pumpInspector(tester, netoscope, hostBrightness: Brightness.light);

    await tester.tap(find.byTooltip('Inspector settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(netoscope.settings.themeMode, InspectorThemeMode.dark);
    expect(brightnessAt(tester, find.text('Dark')), Brightness.dark);
    expect(brightnessAt(tester, find.text('/login')), Brightness.dark);

    // The sheet surface follows too, so text stays readable on it.
    Color sheetColor() => tester
        .widget<Material>(find
            .descendant(
              of: find.byType(InspectorSettingsSheet),
              matching: find.byType(Material),
            )
            .first)
        .color!;
    expect(sheetColor(),
        inspectorTheme(Brightness.dark).bottomSheetTheme.backgroundColor);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(brightnessAt(tester, find.text('Dark')), Brightness.light);
    expect(sheetColor(),
        inspectorTheme(Brightness.light).bottomSheetTheme.backgroundColor);

    // "System" inside the sheet still resolves to the app's brightness.
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(brightnessAt(tester, find.text('Dark')), Brightness.light);
  });

  testWidgets('the settings sheet switches on the first frame', (tester) async {
    final netoscope = netoscopeWith(InspectorThemeMode.dark);
    await pumpInspector(tester, netoscope, hostBrightness: Brightness.light);
    await tester.tap(find.byTooltip('Inspector settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.pump(); // the settings stream delivers asynchronously

    // No fade: text must not linger in the dark theme's light color.
    final title = tester.renderObject<RenderParagraph>(
      find.text('Floating button'),
    );
    final colorNow = title.text.style?.color;
    await tester.pumpAndSettle();
    expect(title.text.style?.color, colorNow);
    expect(
      colorNow,
      inspectorTheme(Brightness.light).colorScheme.onSurface,
    );
  });
}
