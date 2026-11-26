import 'package:flutter_test/flutter_test.dart';
import 'package:netoscope_shake/netoscope_shake.dart';

void main() {
  final start = DateTime(2026, 11, 26, 12);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));
  const strong = 3.5 * standardGravity;

  group('ShakeDetector', () {
    test('gForce is 1 g at rest', () {
      expect(ShakeDetector.gForce(0, 0, standardGravity), closeTo(1, 1e-9));
      expect(ShakeDetector.gForce(3, 4, 0), closeTo(5 / standardGravity, 1e-9));
    });

    test('ignores samples at or below the threshold', () {
      final detector = ShakeDetector();
      for (var i = 0; i < 20; i++) {
        expect(detector.add(0, 0, standardGravity * 2.7, at(i * 50)), isFalse);
      }
    });

    test('a single jolt is not a shake', () {
      final detector = ShakeDetector();
      expect(detector.add(strong, 0, 0, at(0)), isFalse);
    });

    test('minJolts jolts within the window make a shake', () {
      final detector = ShakeDetector();
      expect(detector.add(strong, 0, 0, at(0)), isFalse);
      expect(detector.add(-strong, 0, 0, at(200)), isTrue);
    });

    test('jolts further apart than the window do not combine', () {
      final detector = ShakeDetector();
      expect(detector.add(strong, 0, 0, at(0)), isFalse);
      expect(detector.add(strong, 0, 0, at(700)), isFalse);
      expect(detector.add(strong, 0, 0, at(900)), isTrue);
    });

    test('ignores jolts during the cooldown, then detects again', () {
      final detector = ShakeDetector();
      detector.add(strong, 0, 0, at(0));
      expect(detector.add(strong, 0, 0, at(100)), isTrue);
      expect(detector.add(strong, 0, 0, at(300)), isFalse);
      expect(detector.add(strong, 0, 0, at(500)), isFalse);
      expect(detector.add(strong, 0, 0, at(1700)), isFalse);
      expect(detector.add(strong, 0, 0, at(1800)), isTrue);
    });

    test('honours a custom threshold and jolt count', () {
      final detector = ShakeDetector(threshold: 1.5, minJolts: 3);
      const medium = 2 * standardGravity;
      expect(detector.add(medium, 0, 0, at(0)), isFalse);
      expect(detector.add(medium, 0, 0, at(100)), isFalse);
      expect(detector.add(medium, 0, 0, at(200)), isTrue);
    });

    test('reset clears jolts and cooldown', () {
      final detector = ShakeDetector();
      detector.add(strong, 0, 0, at(0));
      detector.add(strong, 0, 0, at(100));
      detector.reset();
      expect(detector.add(strong, 0, 0, at(200)), isFalse);
      expect(detector.add(strong, 0, 0, at(300)), isTrue);
    });
  });
}
