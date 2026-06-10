import 'package:flutter_test/flutter_test.dart';
import 'package:ignaci_imak/data/types.dart';
import 'package:ignaci_imak/services/audio_handler.dart';

void main() {
  group('AudioHandler.computePageStartTimes', () {
    test('returns empty list for empty steps', () {
      expect(AudioHandler.computePageStartTimes([], Duration.zero), isEmpty);
    });

    test('single fix step gets full duration', () {
      final steps = [
        PrayerStep(
          index: 0,
          description: 'step1',
          type: PrayerStepType.fix,
          time: const Duration(seconds: 30),
          voices: ['a.mp3'],
          prayer: 'p1',
        ),
      ];
      final result = AudioHandler.computePageStartTimes(
        steps,
        const Duration(seconds: 60),
      );
      expect(result, hasLength(1));
      expect(result[0], const Duration(seconds: 60));
    });

    test('single flex step gets full duration', () {
      final steps = [
        PrayerStep(
          index: 0,
          description: 'step1',
          type: PrayerStepType.flex,
          time: const Duration(seconds: 30),
          voices: ['a.mp3'],
          prayer: 'p1',
        ),
      ];
      final result = AudioHandler.computePageStartTimes(
        steps,
        const Duration(seconds: 60),
      );
      expect(result, hasLength(1));
      expect(result[0], const Duration(seconds: 60));
    });

    test('two fix steps proportionally share total', () {
      final steps = [
        PrayerStep(
          index: 0,
          description: 'step1',
          type: PrayerStepType.fix,
          time: const Duration(seconds: 10),
          voices: ['a.mp3'],
          prayer: 'p1',
        ),
        PrayerStep(
          index: 1,
          description: 'step2',
          type: PrayerStepType.fix,
          time: const Duration(seconds: 20),
          voices: ['b.mp3'],
          prayer: 'p1',
        ),
      ];
      final result = AudioHandler.computePageStartTimes(
        steps,
        const Duration(seconds: 60),
      );
      expect(result, hasLength(2));
      // 60 * 10/30 = 20, 60 * 20/30 = 40
      // running total: 60, 60-20=40
      expect(result[0], const Duration(seconds: 60));
      expect(result[1], const Duration(seconds: 40));
    });

    test('fix steps take exact time, flex gets remaining', () {
      final steps = [
        PrayerStep(
          index: 0,
          description: 'fix1',
          type: PrayerStepType.fix,
          time: const Duration(seconds: 10),
          voices: ['a.mp3'],
          prayer: 'p1',
        ),
        PrayerStep(
          index: 1,
          description: 'flex1',
          type: PrayerStepType.flex,
          time: const Duration(seconds: 30),
          voices: ['b.mp3'],
          prayer: 'p1',
        ),
      ];
      // fix = 10, flex = 30, total = 40
      // flexAvailable = 60 - 10 = 50
      // flex1 gets 50 * 30/30 = 50
      // running: 60, 60-10=50, 50-50=0
      final result = AudioHandler.computePageStartTimes(
        steps,
        const Duration(seconds: 60),
      );
      expect(result, hasLength(2));
      expect(result[0], const Duration(seconds: 60));
      expect(result[1], const Duration(seconds: 50));
    });

    test('mixed fix and flex steps', () {
      final steps = [
        PrayerStep(
          index: 0,
          description: 'fix1',
          type: PrayerStepType.fix,
          time: const Duration(seconds: 5),
          voices: ['a.mp3'],
          prayer: 'p1',
        ),
        PrayerStep(
          index: 1,
          description: 'flex1',
          type: PrayerStepType.flex,
          time: const Duration(seconds: 10),
          voices: ['b.mp3'],
          prayer: 'p1',
        ),
        PrayerStep(
          index: 2,
          description: 'flex2',
          type: PrayerStepType.flex,
          time: const Duration(seconds: 20),
          voices: ['c.mp3'],
          prayer: 'p1',
        ),
      ];
      // fix = 5, flex = 30, total = 35
      // flexAvailable = 60 - 5 = 55
      // flex1: 55 * 10/30 = 18.33 -> 18
      // flex2: 55 * 20/30 = 36.66 -> 36
      // running: 60, 60-5=55, 55-18=37, 37-36=1
      final result = AudioHandler.computePageStartTimes(
        steps,
        const Duration(seconds: 60),
      );
      expect(result, hasLength(3));
      expect(result[0], const Duration(seconds: 60));
      expect(result[1], const Duration(seconds: 55));
      expect(result[2], const Duration(seconds: 37));
    });

    test('zero total duration returns zeros', () {
      final steps = [
        PrayerStep(
          index: 0,
          description: 'step1',
          type: PrayerStepType.fix,
          time: Duration.zero,
          voices: ['a.mp3'],
          prayer: 'p1',
        ),
      ];
      final result = AudioHandler.computePageStartTimes(steps, Duration.zero);
      expect(result, hasLength(1));
      expect(result[0], Duration.zero);
    });
  });
}
