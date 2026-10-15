import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';

class GameCatalogSnapshot {
  const GameCatalogSnapshot({required this.venue, required this.games});

  final VenueContext venue;
  final List<Map<String, dynamic>> games;
}

class GameCatalogRepository {
  GameCatalogRepository(this._client);

  final SupabaseClient _client;

  Future<GameCatalogSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    List<dynamic> response;
    try {
      response = await _client
          .from('games')
          .select(
            'id, venue_id, name, subtitle, platform, category, image_url, youtube_url, game_mode, '
            'mode_source, pricing_unit, price, match_minutes, time_multiplier, '
            'effective_match_seconds, pricing_tiers, is_available, is_trending',
          )
          .eq('venue_id', venue.id)
          .order('name');
    } catch (_) {
      response = await _client
          .from('games')
          .select(
            'id, venue_id, name, subtitle, platform, category, image_url, price, game_mode',
          )
          .eq('venue_id', venue.id)
          .order('name');
    }
    return GameCatalogSnapshot(
      venue: venue,
      games: response.cast<Map<String, dynamic>>(),
    );
  }

  RealtimeChannel subscribe(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel('venue:$venueId:catalog');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'games',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'venue_id',
        value: venueId,
      ),
      callback: (_) => onChange(),
    );
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  Future<void> save({
    required String venueId,
    required Map<String, dynamic> values,
    String? gameId,
  }) async {
    final payload = Map<String, dynamic>.from(values)..['venue_id'] = venueId;
    try {
      if (gameId == null) {
        await _client.from('games').insert(payload);
      } else {
        await _client.from('games').update(payload).eq('id', gameId);
      }
    } on PostgrestException catch (_) {
      // Fallback: strip optional schema columns if they cause Postgrest exceptions
      final sanitized = Map<String, dynamic>.from(payload)
        ..remove('youtube_url')
        ..remove('pricing_tiers')
        ..remove('mode_source')
        ..remove('effective_match_seconds');
      if (gameId == null) {
        await _client.from('games').insert(sanitized);
      } else {
        await _client.from('games').update(sanitized).eq('id', gameId);
      }
    }
  }

  Future<void> setAvailability(String gameId, bool isAvailable) async {
    await _client
        .from('games')
        .update({'is_available': isAvailable})
        .eq('id', gameId);
  }

  Future<void> deleteGame(String gameId) async {
    try {
      await _client.from('games').delete().eq('id', gameId);
    } on PostgrestException catch (e) {
      if (e.code == '23503' || e.message.contains('23503') || e.message.contains('foreign key')) {
        await setAvailability(gameId, false);
        throw const PostgrestException(
          message: 'GAME_HAS_HISTORY',
        );
      }
      rethrow;
    }
  }
}
