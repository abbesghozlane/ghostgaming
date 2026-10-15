import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/sessions/domain/session_dashboard_models.dart';

void main() {
  final unrestrictedPost = GamingPost(
    id: 'post-unrestricted',
    name: 'Post 1',
    number: 1,
    device: 'ps5',
    status: 'available',
  );
  final restrictedPost = GamingPost(
    id: 'post-restricted',
    name: 'Post 2',
    number: 2,
    device: 'ps5',
    status: 'available',
    supportedGameIds: const {'football', 'racing'},
  );

  test('an empty supported-game set keeps the existing all-games behavior', () {
    expect(unrestrictedPost.supportsGame('football'), isTrue);
    expect(unrestrictedPost.supportsGame('racing'), isTrue);
    const game = CatalogGame(
      id: 'football',
      name: 'Football',
      mode: 'match_based',
      pricingUnit: 'per_match',
      price: 100,
    );
    expect(unrestrictedPost.priceFor(game), 100);
  });

  test('a configured post only accepts assigned games', () {
    expect(restrictedPost.supportsGame('football'), isTrue);
    expect(restrictedPost.supportsGame('racing'), isTrue);
    expect(restrictedPost.supportsGame('fighter'), isFalse);
  });

  test('starting a session supports reserved posts and compatible games', () {
    final reservedPost = GamingPost(
      id: 'post-reserved',
      name: 'Post réservé',
      number: 4,
      device: 'ps5',
      status: 'reserved',
      supportedGameIds: const {'football'},
    );
    final maintenancePost = GamingPost(
      id: 'post-maintenance',
      name: 'Post maintenance',
      number: 5,
      device: 'ps5',
      status: 'maintenance',
    );
    const football = CatalogGame(
      id: 'football',
      name: 'Football',
      mode: 'match_based',
      pricingUnit: 'per_match',
      price: 100,
    );
    const timeBasedMatchPrice = CatalogGame(
      id: 'time-match',
      name: 'Jeu incompatible',
      mode: 'time_based',
      pricingUnit: 'per_match',
      price: 100,
    );

    expect(
      startablePosts(
        [unrestrictedPost, reservedPost, maintenancePost],
        [football, timeBasedMatchPrice],
      ),
      [unrestrictedPost, reservedPost],
    );
  });

  test('post game assignments are parsed from the repository relation', () {
    final post = GamingPost.fromJson({
      'id': 'post-from-json',
      'name': 'Post 3',
      'number': 3,
      'device': 'pc',
      'status': 'available',
      'post_games': [
        {'game_id': 'racing'},
      ],
      'post_game_prices': [
        {'game_id': 'racing', 'price_override': 125.5},
      ],
    });
    const game = CatalogGame(
      id: 'racing',
      name: 'Racing',
      mode: 'time_based',
      pricingUnit: 'per_hour',
      price: 100,
    );

    expect(post.supportsGame('racing'), isTrue);
    expect(post.supportsGame('football'), isFalse);
    expect(post.priceFor(game), 125.5);
  });

  test('transfer targets exclude posts incompatible with the active game', () {
    final session = ActiveGamingSession(
      id: 'session-1',
      number: 501,
      postId: 'post-unrestricted',
      gameId: 'fighter',
      status: 'active',
      startedAt: DateTime.utc(2026, 1, 1),
      plannedDurationSeconds: 3600,
      totalPausedSeconds: 0,
      matchCount: 0,
      game: null,
      postName: unrestrictedPost.name,
      customerName: null,
    );

    expect(
      transferablePosts([unrestrictedPost, restrictedPost], session),
      isEmpty,
    );
  });

  test('transfer targets keep posts compatible with the active game', () {
    final compatiblePost = GamingPost(
      id: 'post-fighter',
      name: 'Post 3',
      number: 3,
      device: 'ps5',
      status: 'available',
      supportedGameIds: const {'fighter'},
    );
    final session = ActiveGamingSession(
      id: 'session-2',
      number: 502,
      postId: 'post-unrestricted',
      gameId: 'fighter',
      status: 'active',
      startedAt: DateTime.utc(2026, 1, 1),
      plannedDurationSeconds: 3600,
      totalPausedSeconds: 0,
      matchCount: 0,
      game: null,
      postName: unrestrictedPost.name,
      customerName: null,
    );

    expect(transferablePosts([unrestrictedPost, compatiblePost], session), [
      compatiblePost,
    ]);
  });

  test('session countdown uses elapsed time and excludes completed pauses', () {
    final startedAt = DateTime.utc(2026, 10, 5, 10);
    final session = ActiveGamingSession(
      id: 'session-timer',
      number: 503,
      postId: 'post-unrestricted',
      gameId: 'game-1',
      status: 'active',
      startedAt: startedAt,
      plannedDurationSeconds: const Duration(minutes: 60).inSeconds,
      totalPausedSeconds: const Duration(minutes: 5).inSeconds,
      matchCount: 0,
      game: null,
      postName: unrestrictedPost.name,
      customerName: null,
    );

    expect(
      session.remainingSeconds(startedAt.add(const Duration(minutes: 20))),
      const Duration(minutes: 45).inSeconds,
    );
    expect(
      session.remainingSeconds(startedAt.add(const Duration(hours: 2))),
      0,
    );
  });

  test('paused session countdown remains fixed at the pause timestamp', () {
    final startedAt = DateTime.utc(2026, 10, 5, 10);
    final pausedAt = startedAt.add(const Duration(minutes: 20));
    final session = ActiveGamingSession(
      id: 'session-paused',
      number: 504,
      postId: 'post-unrestricted',
      gameId: 'game-1',
      status: 'paused',
      startedAt: startedAt,
      pausedAt: pausedAt,
      plannedDurationSeconds: const Duration(minutes: 60).inSeconds,
      totalPausedSeconds: 0,
      matchCount: 0,
      game: null,
      postName: unrestrictedPost.name,
      customerName: null,
    );

    expect(
      session.remainingSeconds(startedAt.add(const Duration(hours: 2))),
      const Duration(minutes: 40).inSeconds,
    );
  });
}
