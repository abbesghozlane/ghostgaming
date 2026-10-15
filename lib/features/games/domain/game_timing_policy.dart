import 'game_classification_service.dart';

class GameTimingPolicy {
  const GameTimingPolicy({
    this.efootballMultiplier = 1.7,
    this.otherFootballMultiplier = 1.5,
  });

  final double efootballMultiplier;
  final double otherFootballMultiplier;

  double multiplierFor(String gameName) {
    final normalized = gameName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalized.startsWith('efootball')) return efootballMultiplier;
    if (GameClassificationService.classify(gameName) ==
        GameClassification.footballMatch) {
      return otherFootballMultiplier;
    }
    return 1;
  }

  int effectiveMatchSeconds({
    required String gameName,
    required int matchMinutes,
    double? configuredMultiplier,
  }) {
    if (matchMinutes <= 0) {
      throw ArgumentError.value(matchMinutes, 'matchMinutes');
    }
    final multiplier = configuredMultiplier ?? multiplierFor(gameName);
    if (!multiplier.isFinite || multiplier <= 0) {
      throw ArgumentError.value(multiplier, 'configuredMultiplier');
    }
    return (matchMinutes * multiplier * 60).round();
  }

  int plannedDurationSeconds({
    required int matchCount,
    required int effectiveMatchSeconds,
  }) {
    if (matchCount < 0) throw ArgumentError.value(matchCount, 'matchCount');
    if (effectiveMatchSeconds < 0) {
      throw ArgumentError.value(effectiveMatchSeconds, 'effectiveMatchSeconds');
    }
    return matchCount * effectiveMatchSeconds;
  }

  int elapsedSeconds({
    required DateTime startedAt,
    required DateTime now,
    DateTime? pausedAt,
    DateTime? endedAt,
    int totalPausedSeconds = 0,
  }) {
    if (totalPausedSeconds < 0) {
      throw ArgumentError.value(totalPausedSeconds, 'totalPausedSeconds');
    }
    final stopAt = pausedAt ?? endedAt ?? now;
    final elapsed = stopAt.difference(startedAt).inSeconds - totalPausedSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  int remainingSeconds({
    required int plannedDurationSeconds,
    required DateTime startedAt,
    required DateTime now,
    DateTime? pausedAt,
    DateTime? endedAt,
    int totalPausedSeconds = 0,
  }) {
    if (plannedDurationSeconds < 0) {
      throw ArgumentError.value(
        plannedDurationSeconds,
        'plannedDurationSeconds',
      );
    }
    final elapsed = elapsedSeconds(
      startedAt: startedAt,
      now: now,
      pausedAt: pausedAt,
      endedAt: endedAt,
      totalPausedSeconds: totalPausedSeconds,
    );
    final remaining = plannedDurationSeconds - elapsed;
    return remaining < 0 ? 0 : remaining;
  }
}
