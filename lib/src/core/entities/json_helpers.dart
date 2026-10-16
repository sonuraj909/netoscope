/// Tolerant JSON readers for restoring persisted entries.
library;

/// [value] as a `T`, or `null`.
T? readAs<T>(Object? value) => value is T ? value : null;

/// [value] as an `int`, accepting any number.
int? readInt(Object? value) => value is num ? value.toInt() : null;

/// [value] as a string map, or empty.
Map<String, String> readStringMap(Object? value) => value is Map
    ? {
        for (final e in value.entries)
          if (e.value != null) '${e.key}': '${e.value}',
      }
    : const {};

/// [value] as a JSON object, or `null`.
Map<String, Object?>? readObject(Object? value) =>
    value is Map ? value.map((k, v) => MapEntry('$k', v)) : null;

/// The enum value named [name], or [fallback].
T readEnum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// The enum value named [name], or `null`.
T? readEnumOrNull<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
