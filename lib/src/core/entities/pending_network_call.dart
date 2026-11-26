/// An HTTP call that has started but not finished yet.
///
/// Pending calls are tracked by the HTTP integrations (Dio, `package:http`
/// and `dart:io` capture) from the moment a request is sent until it
/// finishes and is recorded as a `NetworkLogEntry` with the same [id].
/// Only redacted values are held, like history entries.
class PendingNetworkCall {
  /// Creates a pending call. [tags] is copied into an unmodifiable list.
  PendingNetworkCall({
    required this.id,
    required String method,
    required this.url,
    required this.startedAt,
    List<String> tags = const [],
  })  : method = method.toUpperCase(),
        tags = List.unmodifiable(tags);

  /// The identifier the finished entry will have.
  final String id;

  /// The upper-cased HTTP method.
  final String method;

  /// The (redacted) request URL.
  final Uri url;

  /// When the request was sent.
  final DateTime startedAt;

  /// Tags applied to the call.
  final List<String> tags;

  /// How long the call has been running.
  Duration get elapsed => DateTime.now().difference(startedAt);

  @override
  String toString() => 'PendingNetworkCall($method $url)';
}
