import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';
import '../../../core/utils/venue_time_zone.dart';

class LoyaltyRepository {
  LoyaltyRepository(this._client);

  final SupabaseClient _client;

  Future<LoyaltySnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    final results = await Future.wait([
      _client
          .from('loyalty_rewards')
          .select(
            'id, name, description, points_cost, stock_quantity, is_active',
          )
          .eq('venue_id', venue.id)
          .order('points_cost'),
      _client
          .from('loyalty_redemptions')
          .select(
            'id, customer_id, status, points_cost, note, created_at, '
            'customers(full_name), loyalty_rewards(name)',
          )
          .eq('venue_id', venue.id)
          .order('created_at', ascending: false)
          .limit(100),
    ]);
    return LoyaltySnapshot(
      venue: venue,
      rewards: (results[0] as List)
          .cast<Map<String, dynamic>>()
          .map(LoyaltyReward.fromJson)
          .toList(growable: false),
      redemptions: (results[1] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => LoyaltyRedemption.fromJson(row, venue.timeZone))
          .toList(growable: false),
    );
  }

  Future<void> saveReward({
    required String venueId,
    required String name,
    required String description,
    required int pointsCost,
    required int? stockQuantity,
    String? rewardId,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 100 ||
        pointsCost < 1 ||
        (stockQuantity != null && stockQuantity < 0)) {
      throw const LoyaltyException('INVALID_REWARD');
    }
    final values = {
      'name': cleanName,
      'description': description.trim().isEmpty ? null : description.trim(),
      'points_cost': pointsCost,
      'stock_quantity': stockQuantity,
    };
    if (rewardId == null) {
      await _client.from('loyalty_rewards').insert({
        ...values,
        'venue_id': venueId,
      });
    } else {
      final updated = await _client
          .from('loyalty_rewards')
          .update(values)
          .eq('id', rewardId)
          .select('id')
          .maybeSingle();
      if (updated == null) {
        throw const LoyaltyException('REWARD_NOT_FOUND');
      }
    }
  }

  Future<void> setRewardActive(String rewardId, bool active) async {
    final updated = await _client
        .from('loyalty_rewards')
        .update({'is_active': active})
        .eq('id', rewardId)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw const LoyaltyException('REWARD_NOT_FOUND');
    }
  }

  Future<void> decideRedemption({
    required String redemptionId,
    required bool approve,
    String? note,
  }) async {
    await executeIdempotentRpc<void>(_client, 'decide_loyalty_redemption', {
      'p_op': OperationId.create(),
      'p_redemption': redemptionId,
      'p_approve': approve,
      'p_note': note,
    });
  }

  RealtimeChannel subscribeVenue(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:loyalty',
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

  RealtimeChannel? subscribeUser(
    void Function() onChange,
    void Function() onError,
  ) {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final channel = _client.channel(
      'user:$userId',
      opts: const RealtimeChannelConfig(private: true),
    )..onBroadcast(event: 'INSERT', callback: (_) => onChange());
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }
}

class LoyaltySnapshot {
  const LoyaltySnapshot({
    required this.venue,
    required this.rewards,
    required this.redemptions,
  });

  final VenueContext venue;
  final List<LoyaltyReward> rewards;
  final List<LoyaltyRedemption> redemptions;
}

class LoyaltyReward {
  const LoyaltyReward({
    required this.id,
    required this.name,
    required this.description,
    required this.pointsCost,
    required this.stockQuantity,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? description;
  final int pointsCost;
  final int? stockQuantity;
  final bool isActive;

  factory LoyaltyReward.fromJson(Map<String, dynamic> json) => LoyaltyReward(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    pointsCost: (json['points_cost'] as num).toInt(),
    stockQuantity: (json['stock_quantity'] as num?)?.toInt(),
    isActive: json['is_active'] as bool? ?? true,
  );
}

class LoyaltyRedemption {
  const LoyaltyRedemption({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.rewardName,
    required this.status,
    required this.pointsCost,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String rewardName;
  final String status;
  final int pointsCost;
  final String? note;
  final DateTime createdAt;

  factory LoyaltyRedemption.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) {
    final createdAt = VenueTimeZone.parse(
      json['created_at'] as String?,
      timeZone,
    );
    if (createdAt == null) {
      throw const FormatException('Invalid loyalty redemption timestamp');
    }
    final customer = json['customers'];
    final reward = json['loyalty_rewards'];
    return LoyaltyRedemption(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      customerName: customer is Map<String, dynamic>
          ? customer['full_name'] as String? ?? 'Client'
          : 'Client',
      rewardName: reward is Map<String, dynamic>
          ? reward['name'] as String? ?? 'Récompense'
          : 'Récompense',
      status: json['status'] as String,
      pointsCost: (json['points_cost'] as num).toInt(),
      note: json['note'] as String?,
      createdAt: createdAt,
    );
  }
}

class LoyaltyException implements Exception {
  const LoyaltyException(this.code);

  final String code;
}
