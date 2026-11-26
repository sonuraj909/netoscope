import 'dart:math' as math;

/// Standard gravity, in m/s².
const double standardGravity = 9.80665;

/// Recognizes shakes in a stream of accelerometer samples.
///
/// Pure Dart with no platform dependency, so it can be unit-tested with
/// synthetic samples. Feed every sample to [add]; it returns `true` when the
/// sample completes a shake.
///
/// A sample is a *jolt* when its total acceleration, gravity included,
/// exceeds [threshold] (in multiples of g). A shake is [minJolts] jolts
/// within [window]. After a shake, samples are ignored for [cooldown], so
/// one vigorous shake triggers once.
class ShakeDetector {
  /// Creates a detector.
  ShakeDetector({
    this.threshold = 2.7,
    this.minJolts = 2,
    this.window = const Duration(milliseconds: 600),
    this.cooldown = const Duration(milliseconds: 1500),
  })  : assert(threshold > 1, 'threshold must exceed 1 g (gravity at rest)'),
        assert(minJolts > 0, 'minJolts must be positive');

  /// The total acceleration, in g, a sample must exceed to count as a jolt.
  final double threshold;

  /// How many jolts within [window] make a shake.
  final int minJolts;

  /// The time span in which [minJolts] jolts must occur.
  final Duration window;

  /// How long after a shake further samples are ignored.
  final Duration cooldown;

  final List<DateTime> _jolts = [];
  DateTime? _lastShake;

  /// The total acceleration of a sample, in g.
  static double gForce(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z) / standardGravity;

  /// Adds a sample (in m/s², gravity included) taken at [time]. Returns
  /// `true` when it completes a shake.
  bool add(double x, double y, double z, DateTime time) {
    final last = _lastShake;
    if (last != null && time.difference(last) < cooldown) return false;
    if (gForce(x, y, z) <= threshold) return false;
    _jolts
      ..add(time)
      ..removeWhere((jolt) => time.difference(jolt) > window);
    if (_jolts.length < minJolts) return false;
    _jolts.clear();
    _lastShake = time;
    return true;
  }

  /// Forgets past jolts and any cooldown in progress.
  void reset() {
    _jolts.clear();
    _lastShake = null;
  }
}
