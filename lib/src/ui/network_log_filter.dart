import '../core/entities/network_log_entry.dart';

/// Status groups offered by the inspector's filter.
enum StatusFilter {
  /// Every call.
  all('All'),

  /// 2xx responses.
  success('2xx'),

  /// 3xx responses.
  redirect('3xx'),

  /// 4xx responses.
  clientError('4xx'),

  /// 5xx responses.
  serverError('5xx'),

  /// Calls without a response: failures and cancellations.
  failed('Failed');

  const StatusFilter(this.label);

  /// A short label for the filter chip.
  final String label;

  /// Whether [entry] belongs to this group.
  bool matches(NetworkLogEntry entry) {
    final code = entry.statusCode;
    return switch (this) {
      StatusFilter.all => true,
      StatusFilter.success => code != null && code >= 200 && code < 300,
      StatusFilter.redirect => code != null && code >= 300 && code < 400,
      StatusFilter.clientError => code != null && code >= 400 && code < 500,
      StatusFilter.serverError => code != null && code >= 500,
      StatusFilter.failed => code == null,
    };
  }
}

/// An immutable set of inspector filters.
class NetworkLogFilter {
  /// Creates a filter. The defaults match every entry.
  const NetworkLogFilter({
    this.query = '',
    this.method,
    this.status = StatusFilter.all,
    this.onlySlow = false,
  });

  /// Case-insensitive text that the URL must contain.
  final String query;

  /// The required HTTP method, or `null` for any.
  final String? method;

  /// The required status group.
  final StatusFilter status;

  /// Whether only calls at or above the slow threshold are kept.
  final bool onlySlow;

  /// Whether any filter is active.
  bool get isActive =>
      query.trim().isNotEmpty ||
      method != null ||
      status != StatusFilter.all ||
      onlySlow;

  /// Returns a copy with the given fields replaced. Pass [clearMethod] to
  /// remove the method filter.
  NetworkLogFilter copyWith({
    String? query,
    String? method,
    bool clearMethod = false,
    StatusFilter? status,
    bool? onlySlow,
  }) =>
      NetworkLogFilter(
        query: query ?? this.query,
        method: clearMethod ? null : method ?? this.method,
        status: status ?? this.status,
        onlySlow: onlySlow ?? this.onlySlow,
      );

  /// Whether [entry] passes every filter.
  bool matches(NetworkLogEntry entry, {required Duration slowThreshold}) {
    final needle = query.trim().toLowerCase();
    if (needle.isNotEmpty &&
        !entry.url.toString().toLowerCase().contains(needle)) {
      return false;
    }
    if (method != null && entry.method != method) return false;
    if (!status.matches(entry)) return false;
    if (onlySlow && !entry.isSlower(slowThreshold)) return false;
    return true;
  }

  /// The entries that pass every filter, in their original order.
  List<NetworkLogEntry> apply(
    Iterable<NetworkLogEntry> entries, {
    required Duration slowThreshold,
  }) =>
      [
        for (final entry in entries)
          if (matches(entry, slowThreshold: slowThreshold)) entry,
      ];
}
