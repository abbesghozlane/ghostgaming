import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/utils/venue_time_zone.dart';

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('UNAUTHENTICATED');
    final venue = await VenueRepository(_client).currentVenue();
    final rows = await _client
        .from('notifications')
        .select(
          'id, type, title, body, reference_type, reference_id, data, is_read, created_at',
        )
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .cast<Map<String, dynamic>>()
        .map((row) => AppNotification.fromJson(row, venue.timeZone))
        .toList(growable: false);
  }

  Future<void> markRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  Future<void> markAllRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthException('UNAUTHENTICATED');
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_id', userId)
        .eq('is_read', false);
  }

  RealtimeChannel subscribe(
    String userId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'user:$userId',
      opts: const RealtimeChannelConfig(private: true),
    );

    // Listen to realtime broadcast changes sent by trigger app.broadcast_user()
    channel.onBroadcast(
      event: '*',
      callback: (_) {
        try {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        } catch (_) {}
        onChange();
      },
    );

    // Listen to direct postgres changes on notifications table for the user
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: userId,
      ),
      callback: (_) {
        try {
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.heavyImpact();
        } catch (_) {}
        onChange();
      },
    );

    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });

    return channel;
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.referenceType,
    required this.referenceId,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;
  final String? referenceType;
  final String? referenceId;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) {
    final createdAt = VenueTimeZone.parse(
      json['created_at'] as String?,
      timeZone,
    );
    if (createdAt == null) {
      throw const FormatException('Invalid notification creation timestamp');
    }
    return AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      isRead: json['is_read'] as bool,
      createdAt: createdAt,
    );
  }

  String destinationForRole(String? role) {
    if (referenceType == 'order' || referenceType == 'invoice') {
      return '/invoices';
    }
    if (referenceType == 'reservation') {
      return '/booking?reservationId=${Uri.encodeQueryComponent(referenceId ?? '')}';
    }
    if (referenceType == 'session' ||
        referenceType == 'session_request' ||
        referenceType == 'post') {
      final sessionId = referenceType == 'session_request'
          ? data['session_id'] as String?
          : referenceId ?? data['session_id'] as String?;
      if (role == 'customer') {
        return sessionId == null
            ? '/customer/home'
            : '/customer/home?sessionId=${Uri.encodeQueryComponent(sessionId)}';
      }
      return sessionId == null
          ? '/home'
          : '/home?sessionId=${Uri.encodeQueryComponent(sessionId)}';
    }
    return role == 'customer' ? '/customer/home' : '/home';
  }
}
