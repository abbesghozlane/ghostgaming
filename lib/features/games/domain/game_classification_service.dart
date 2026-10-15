enum GameClassification { footballMatch, timeBased, other }

enum GameMode { matchBased, timeBased, custom }

class GameClassificationService {
  const GameClassificationService._();

  static GameClassification classify(String gameName) {
    final normalized = _normalize(gameName);
    if (normalized.isEmpty) return GameClassification.other;

    final compact = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final isFootball =
        compact.contains('efootball') ||
        compact.contains('pes') ||
        compact.contains('fifa') ||
        compact.contains('football') ||
        compact.contains('soccer') ||
        compact.contains('ufl') ||
        compact.contains('dls') ||
        compact.contains('dreamleague') ||
        RegExp(r'(?:easports)?fc(?:20)?(?:\d{2})?').hasMatch(compact);

    return isFootball
        ? GameClassification.footballMatch
        : GameClassification.timeBased;
  }

  static GameMode resolveMode(String gameName, {GameMode? ownerOverride}) {
    if (ownerOverride != null) return ownerOverride;
    return classify(gameName) == GameClassification.footballMatch
        ? GameMode.matchBased
        : GameMode.timeBased;
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp('[àáâãäå]'), 'a')
        .replaceAll(RegExp('[èéêë]'), 'e')
        .replaceAll(RegExp('[ìíîï]'), 'i')
        .replaceAll(RegExp('[òóôõö]'), 'o')
        .replaceAll(RegExp('[ùúûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll('œ', 'oe')
        .replaceAll('æ', 'ae')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
