import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/games/domain/game_classification_service.dart';
import 'package:ghostgaming/features/games/domain/game_timing_policy.dart';

void main() {
  group('GameClassificationService', () {
    test('recognizes football aliases regardless of case and formatting', () {
      for (final name in [
        'eFootball',
        'eFootball 2026',
        'eFootball PES 2025',
        'PES 2021',
        'EA SPORTS FC 26',
        'FC 25',
        'FIFA 24',
      ]) {
        expect(
          GameClassificationService.classify(name),
          GameClassification.footballMatch,
          reason: name,
        );
      }
      expect(
        GameClassificationService.classify('ÉA   SPORTS FC 26'),
        GameClassification.footballMatch,
      );
    });

    test('classifies non-football names as time based and blank as other', () {
      expect(
        GameClassificationService.classify('Tekken 8'),
        GameClassification.timeBased,
      );
      expect(
        GameClassificationService.classify('  '),
        GameClassification.other,
      );
    });

    test('an owner override always takes precedence', () {
      expect(
        GameClassificationService.resolveMode(
          'eFootball 2026',
          ownerOverride: GameMode.timeBased,
        ),
        GameMode.timeBased,
      );
      expect(
        GameClassificationService.resolveMode(
          'Tekken 8',
          ownerOverride: GameMode.matchBased,
        ),
        GameMode.matchBased,
      );
    });
  });

  group('GameTimingPolicy', () {
    const policy = GameTimingPolicy();

    test('uses the football station-time multipliers', () {
      expect(
        policy.effectiveMatchSeconds(
          gameName: 'eFootball 2026',
          matchMinutes: 10,
        ),
        1020,
      );
      expect(
        policy.effectiveMatchSeconds(gameName: 'FIFA 26', matchMinutes: 10),
        900,
      );
      expect(
        policy.effectiveMatchSeconds(gameName: 'Tekken 8', matchMinutes: 10),
        600,
      );
    });

    test('calculates multi-match planned duration', () {
      final duration = policy.effectiveMatchSeconds(
        gameName: 'eFootball',
        matchMinutes: 10,
      );
      expect(
        policy.plannedDurationSeconds(
          matchCount: 3,
          effectiveMatchSeconds: duration,
        ),
        3060,
      );
    });

    test('calculates remaining time from timestamps, including pauses', () {
      final start = DateTime.utc(2026, 10, 3, 12);
      expect(
        policy.remainingSeconds(
          plannedDurationSeconds: 1020,
          startedAt: start,
          now: start.add(const Duration(minutes: 5)),
        ),
        720,
      );
      expect(
        policy.remainingSeconds(
          plannedDurationSeconds: 1020,
          startedAt: start,
          now: start.add(const Duration(minutes: 10)),
          pausedAt: start.add(const Duration(minutes: 5)),
          totalPausedSeconds: 60,
        ),
        780,
      );
    });

    test('uses the recorded end timestamp and never returns negative time', () {
      final start = DateTime.utc(2026, 10, 3, 12);
      expect(
        policy.remainingSeconds(
          plannedDurationSeconds: 60,
          startedAt: start,
          now: start.add(const Duration(hours: 1)),
          endedAt: start.add(const Duration(minutes: 2)),
        ),
        0,
      );
    });
  });
}
