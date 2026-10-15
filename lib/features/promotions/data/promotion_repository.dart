import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/utils/venue_time_zone.dart';

class PromotionRepository {
  PromotionRepository(this._client);

  final SupabaseClient _client;

  Future<PromotionSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    final rows = await _client
        .from('promotions')
        .select(
          'id, name, description, discount_percent, starts_at, ends_at, is_active',
        )
        .eq('venue_id', venue.id)
        .order('starts_at', ascending: false);
    return PromotionSnapshot(
      venue: venue,
      promotions: rows
          .cast<Map<String, dynamic>>()
          .map((row) => Promotion.fromJson(row, venue.timeZone))
          .toList(growable: false),
    );
  }

  Future<void> save({
    required String venueId,
    required String name,
    required String description,
    required double discountPercent,
    required DateTime startsAt,
    required DateTime endsAt,
    required String timeZone,
    String? promotionId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 100 ||
        !discountPercent.isFinite ||
        discountPercent <= 0 ||
        discountPercent > 100 ||
        endsAt.isBefore(startsAt) ||
        endsAt.isAtSameMomentAs(startsAt)) {
      throw const PromotionException('INVALID_PROMOTION');
    }
    final values = {
      'name': cleanName,
      'description': description.trim().isEmpty ? null : description.trim(),
      'discount_percent': discountPercent,
      'starts_at': VenueTimeZone.toUtc(startsAt, timeZone).toIso8601String(),
      'ends_at': VenueTimeZone.toUtc(endsAt, timeZone).toIso8601String(),
    };
    if (promotionId == null) {
      await _client.from('promotions').insert({
        ...values,
        'venue_id': venueId,
      });
    } else {
      await _client
          .from('promotions')
          .update(values)
          .eq('id', promotionId);
    }
  }

  Future<void> setActive(String promotionId, bool isActive) async {
    await _client
        .from('promotions')
        .update({'is_active': isActive})
        .eq('id', promotionId);
  }

  RealtimeChannel subscribe(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:promotions',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }
}

class PromotionSnapshot {
  const PromotionSnapshot({required this.venue, required this.promotions});

  final VenueContext venue;
  final List<Promotion> promotions;
}

class Promotion {
  const Promotion({
    required this.id,
    required this.name,
    required this.description,
    required this.discountPercent,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? description;
  final double discountPercent;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;

  bool activeAt(DateTime now) =>
      isActive && !startsAt.isAfter(now) && endsAt.isAfter(now);

  factory Promotion.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) {
    final startsAt = VenueTimeZone.parse(
      json['starts_at'] as String?,
      timeZone,
    );
    final endsAt = VenueTimeZone.parse(json['ends_at'] as String?, timeZone);
    if (startsAt == null || endsAt == null) {
      throw const FormatException('Invalid promotion date');
    }
    return Promotion(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      discountPercent: (json['discount_percent'] as num).toDouble(),
      startsAt: startsAt,
      endsAt: endsAt,
      isActive: json['is_active'] as bool,
    );
  }
}

class PromotionException implements Exception {
  const PromotionException(this.code);

  final String code;
}
