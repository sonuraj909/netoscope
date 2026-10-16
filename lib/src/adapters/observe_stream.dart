import 'dart:async';

/// Returns a stream that emits exactly what [source] emits while reporting
/// events to the callbacks.
///
/// Single-subscription sources stay single-subscription and keep their
/// backpressure: pause, resume and cancel are forwarded to [source], and
/// nothing is read until the caller listens.
///
/// Broadcast sources are returned unchanged; an extra listener reports
/// events once, however many listeners the app adds. Call the returned
/// cancel function to detach it.
///
/// Callback failures are swallowed so observation never affects the app.
Stream<T> observeStream<T>(
  Stream<T> source, {
  void Function(T event)? onData,
  void Function(Object error)? onError,
  void Function()? onDone,
  void Function()? onCancel,
}) {
  void safely(void Function() action) {
    try {
      action();
    } catch (_) {
      // Observation must never affect the observed stream.
    }
  }

  if (source.isBroadcast) {
    source.listen(
      (event) => safely(() => onData?.call(event)),
      onError: (Object error) => safely(() => onError?.call(error)),
      onDone: () => safely(() => onDone?.call()),
    );
    return source;
  }

  StreamSubscription<T>? subscription;
  final controller = StreamController<T>(sync: true);
  controller
    ..onListen = () {
      subscription = source.listen(
        (event) {
          safely(() => onData?.call(event));
          controller.add(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          safely(() => onError?.call(error));
          controller.addError(error, stackTrace);
        },
        onDone: () {
          safely(() => onDone?.call());
          controller.close();
        },
      );
    }
    ..onPause = () {
      subscription?.pause();
    }
    ..onResume = () {
      subscription?.resume();
    }
    ..onCancel = () {
      safely(() => onCancel?.call());
      return subscription?.cancel();
    };
  return controller.stream;
}
