import 'package:flutter/material.dart';

import '../../config/netoscope_settings.dart';
import '../../config/network_logger_config.dart';
import '../../network_inspector.dart';

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// A translucent version of [color], for pill and card backgrounds.
Color tint(Color color, [int alpha = 36]) => color.withAlpha(alpha);

/// The accent color for an HTTP method or protocol label.
Color methodColor(BuildContext context, String label) {
  final dark = _isDark(context);
  final MaterialColor base = switch (label.split(' ').first.toUpperCase()) {
    'GET' => Colors.blue,
    'POST' => Colors.green,
    'PUT' => Colors.orange,
    'PATCH' => Colors.purple,
    'DELETE' => Colors.red,
    'WS' => Colors.teal,
    'SSE' => Colors.indigo,
    'MQTT' => Colors.brown,
    'GRPC' || 'GRPC-WEB' => Colors.cyan,
    _ => Colors.blueGrey,
  };
  return dark ? base.shade300 : base.shade700;
}

/// Colors used for syntax highlighting, tuned per brightness.
class SyntaxPalette {
  /// Creates a palette.
  const SyntaxPalette({
    required this.background,
    required this.plain,
    required this.key,
    required this.string,
    required this.number,
    required this.keyword,
    required this.punctuation,
    required this.tag,
    required this.attribute,
    required this.comment,
    required this.redacted,
    required this.redactedBackground,
    required this.lineNumber,
  });

  /// The palette for the current theme.
  factory SyntaxPalette.of(BuildContext context) =>
      _isDark(context) ? _dark : _light;

  static const _light = SyntaxPalette(
    background: Color(0xFFF6F8FA),
    plain: Color(0xFF1F2328),
    key: Color(0xFF0550AE),
    string: Color(0xFF116329),
    number: Color(0xFF953800),
    keyword: Color(0xFFCF222E),
    punctuation: Color(0xFF6E7781),
    tag: Color(0xFF0550AE),
    attribute: Color(0xFF8250DF),
    comment: Color(0xFF6E7781),
    redacted: Color(0xFFB3261E),
    redactedBackground: Color(0x22B3261E),
    lineNumber: Color(0xFF8C959F),
  );

  static const _dark = SyntaxPalette(
    background: Color(0xFF161B22),
    plain: Color(0xFFE6EDF3),
    key: Color(0xFF79C0FF),
    string: Color(0xFFA5D6A7),
    number: Color(0xFFFFB86C),
    keyword: Color(0xFFFF7B9C),
    punctuation: Color(0xFF8B949E),
    tag: Color(0xFF7EE787),
    attribute: Color(0xFFD2A8FF),
    comment: Color(0xFF8B949E),
    redacted: Color(0xFFFFA198),
    redactedBackground: Color(0x33FFA198),
    lineNumber: Color(0xFF6E7681),
  );

  /// Code block background.
  final Color background;

  /// Unclassified text.
  final Color plain;

  /// Object keys and field names.
  final Color key;

  /// String values.
  final Color string;

  /// Numbers.
  final Color number;

  /// Booleans, null and language keywords.
  final Color keyword;

  /// Braces, brackets, commas and operators.
  final Color punctuation;

  /// Markup tag names.
  final Color tag;

  /// Markup attribute names and GraphQL variables.
  final Color attribute;

  /// Comments.
  final Color comment;

  /// Redacted values.
  final Color redacted;

  /// Background behind redacted values.
  final Color redactedBackground;

  /// Line numbers.
  final Color lineNumber;
}

/// The monospace style used for code.
const TextStyle codeTextStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Courier New', 'Courier'],
  fontSize: 12.5,
  height: 1.5,
);

/// The inspector's own theme: a neutral, high-contrast palette that looks
/// the same whatever theme the host app uses. Follows [brightness].
///
/// [fontFamily] keeps the host app's font, if it sets one.
ThemeData inspectorTheme(Brightness brightness, {String? fontFamily}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4F6BED),
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFF8EA2FF) : const Color(0xFF3B55D9),
    surface: dark ? const Color(0xFF111318) : const Color(0xFFFFFFFF),
    onSurface: dark ? const Color(0xFFE7E9EE) : const Color(0xFF15181E),
    onSurfaceVariant: dark ? const Color(0xFF9AA3B2) : const Color(0xFF5B6472),
    surfaceContainerLowest:
        dark ? const Color(0xFF0C0E12) : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        dark ? const Color(0xFF161920) : const Color(0xFFF8F9FB),
    surfaceContainer: dark ? const Color(0xFF1B1F27) : const Color(0xFFF2F4F7),
    surfaceContainerHigh:
        dark ? const Color(0xFF21262F) : const Color(0xFFECEFF3),
    surfaceContainerHighest:
        dark ? const Color(0xFF282D38) : const Color(0xFFE5E8ED),
    outline: dark ? const Color(0xFF4A5160) : const Color(0xFFB8BEC8),
    outlineVariant: dark ? const Color(0xFF2A2F3A) : const Color(0xFFE3E6EB),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.compact,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withAlpha(dark ? 60 : 30),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 2),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
    ),
  );
}

/// Applies [inspectorTheme] to [child], in the brightness chosen by
/// [Netoscope.settings]' theme mode (the host's brightness for
/// [InspectorThemeMode.system]). Rebuilds when the mode is switched.
class InspectorThemeScope extends StatelessWidget {
  /// Creates the scope.
  const InspectorThemeScope({
    super.key,
    required this.netoscope,
    required this.child,
  });

  /// The logger whose theme setting is applied.
  final Netoscope netoscope;

  /// The inspector content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final host = Theme.of(context);
    // Nested scopes (pushed routes, sheets) see the inspector theme as their
    // host, so the app's own brightness is carried down separately.
    final hostBrightness = _HostBrightness.maybeOf(context) ?? host.brightness;
    return StreamBuilder<NetoscopeSettings>(
      stream: netoscope.settingsChanges,
      initialData: netoscope.settings,
      builder: (context, _) {
        final brightness = switch (netoscope.settings.themeMode) {
          InspectorThemeMode.system => hostBrightness,
          InspectorThemeMode.light => Brightness.light,
          InspectorThemeMode.dark => Brightness.dark,
        };
        return _HostBrightness(
          brightness: hostBrightness,
          child: Theme(
            data: inspectorTheme(
              brightness,
              fontFamily: host.textTheme.bodyMedium?.fontFamily,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// The host app's brightness, outside any inspector theme. An
/// [InheritedTheme] so modal sheets and dialogs capture it too.
class _HostBrightness extends InheritedTheme {
  const _HostBrightness({required this.brightness, required super.child});

  final Brightness brightness;

  static Brightness? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HostBrightness>()?.brightness;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _HostBrightness(brightness: brightness, child: child);

  @override
  bool updateShouldNotify(_HostBrightness oldWidget) =>
      brightness != oldWidget.brightness;
}

/// Numbers that line up in columns.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// Status colors for charts (validated status palette). Always pair them
/// with a label or icon; color never carries meaning alone.
abstract final class StatusColors {
  /// Success.
  static const Color good = Color(0xFF0CA30C);

  /// Client errors and other attention-worthy states.
  static const Color warning = Color(0xFFFAB219);

  /// Server errors.
  static const Color serious = Color(0xFFEC835A);

  /// Failures without a response.
  static const Color critical = Color(0xFFD03B3B);

  /// Neutral states (redirects, cancellations, other).
  static const Color neutral = Color(0xFF8A94A6);

  /// The chart color for a status class (`2xx`, `3xx`, `4xx`, `5xx`,
  /// `Failed`).
  static Color forStatusClass(String statusClass) => switch (statusClass) {
        '2xx' => good,
        '4xx' => warning,
        '5xx' => serious,
        'Failed' => critical,
        _ => neutral,
      };
}
