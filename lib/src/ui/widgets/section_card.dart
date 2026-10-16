import 'package:flutter/material.dart';

/// Provides the redaction mask to payload viewers so redacted values can be
/// highlighted.
class RedactionMaskScope extends InheritedWidget {
  /// Creates the scope.
  const RedactionMaskScope({
    super.key,
    required this.mask,
    required super.child,
  });

  /// The configured redaction mask.
  final String mask;

  /// The nearest mask, or `***`.
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RedactionMaskScope>()?.mask ??
      '***';

  @override
  bool updateShouldNotify(RedactionMaskScope oldWidget) =>
      oldWidget.mask != mask;
}

/// A titled group of details: an uppercase label above its content.
class SectionCard extends StatelessWidget {
  /// Creates a section.
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.color,
    this.uppercaseTitle = true,
  });

  /// Whether the title is shown in upper case. Turn off for case-sensitive
  /// names such as GraphQL operations.
  final bool uppercaseTitle;

  /// The section title.
  final String title;

  /// An optional icon shown before the title.
  final IconData? icon;

  /// An optional trailing widget, such as a count or an action.
  final Widget? trailing;

  /// An optional accent color for the title (for example, errors).
  final Color? color;

  /// The section content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: accent),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    uppercaseTitle ? title.toUpperCase() : title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// A bordered property table: one row per pair, separated by hairlines.
class KeyValueTable extends StatelessWidget {
  /// Creates a table.
  const KeyValueTable({
    super.key,
    required this.rows,
    this.emptyText = '–',
    this.monospaceValues = false,
    this.accent,
  });

  /// The rows shown.
  final List<MapEntry<String, String>> rows;

  /// Shown when there are no rows.
  final String emptyText;

  /// Whether values use a monospace font (headers, IDs).
  final bool monospaceValues;

  /// An optional border and background accent (for example, errors).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final keyStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      height: 1.45,
    );
    final valueStyle = monospaceValues
        ? TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: const ['Menlo', 'Courier New'],
            fontSize: 12.5,
            height: 1.45,
            color: scheme.onSurface,
          )
        : theme.textTheme.bodyMedium?.copyWith(height: 1.45);
    final accent = this.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent == null ? scheme.surfaceContainerLow : tintOf(accent),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent ?? scheme.outlineVariant),
      ),
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                emptyText,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 300;
                final keyWidth = constraints.maxWidth < 420 ? 112.0 : 150.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, row) in rows.indexed) ...[
                      if (index > 0) Divider(color: accent?.withAlpha(60)),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: stacked
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(row.key, style: keyStyle),
                                  const SizedBox(height: 2),
                                  SelectableText(row.value, style: valueStyle),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: keyWidth,
                                    child: Text(row.key, style: keyStyle),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: SelectableText(
                                      row.value,
                                      style: valueStyle,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  /// A faint background for an accented table.
  static Color tintOf(Color color) => color.withAlpha(18);
}
