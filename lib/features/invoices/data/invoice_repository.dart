import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/utils/venue_time_zone.dart';

class InvoiceRepository {
  InvoiceRepository(this._client);

  final SupabaseClient _client;

  Future<InvoiceHistorySnapshot> load() async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('UNAUTHENTICATED');
    final venue = await VenueRepository(_client).currentVenue();

    List<Map<String, dynamic>> rows;
    if (venue.role == 'customer') {
      final customers =
          (await _client
                  .from('customers')
                  .select('id')
                  .eq('venue_id', venue.id)
                  .eq('user_id', user.id))
              .cast<Map<String, dynamic>>();
      final customerIds = customers
          .map((customer) => customer['id'] as String)
          .toList(growable: false);
      if (customerIds.isEmpty) {
        return InvoiceHistorySnapshot(
          venueId: venue.id,
          userId: user.id,
          isCustomer: true,
          invoices: const [],
        );
      }
      rows =
          (await _client
                  .from('invoices')
                  .select('id, number, total, session_id, order_id, created_at')
                  .eq('venue_id', venue.id)
                  .inFilter('customer_id', customerIds)
                  .order('created_at', ascending: false)
                  .limit(100))
              .cast<Map<String, dynamic>>();
    } else {
      rows =
          (await _client
                  .from('invoices')
                  .select('id, number, total, session_id, order_id, created_at')
                  .eq('venue_id', venue.id)
                  .order('created_at', ascending: false)
                  .limit(100))
              .cast<Map<String, dynamic>>();
    }

    return InvoiceHistorySnapshot(
      venueId: venue.id,
      userId: user.id,
      isCustomer: venue.role == 'customer',
      invoices: rows
          .map((row) => InvoiceRecord.fromJson(row, venue.timeZone))
          .toList(growable: false),
    );
  }

  RealtimeChannel subscribe(
    String venueId,
    String userId, {
    required bool isCustomer,
    required void Function() onChange,
    required void Function() onError,
  }) {
    final topic = isCustomer ? 'user:$userId' : 'venue:$venueId:orders';
    final channel = _client.channel(
      topic,
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE']) {
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

class InvoiceHistorySnapshot {
  const InvoiceHistorySnapshot({
    required this.venueId,
    required this.userId,
    required this.isCustomer,
    required this.invoices,
  });

  final String venueId;
  final String userId;
  final bool isCustomer;
  final List<InvoiceRecord> invoices;
}

class InvoiceRecord {
  const InvoiceRecord({
    required this.id,
    required this.number,
    required this.total,
    required this.isSessionInvoice,
    required this.createdAt,
  });

  final String id;
  final int number;
  final double total;
  final bool isSessionInvoice;
  final DateTime createdAt;

  factory InvoiceRecord.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) {
    final createdAt = VenueTimeZone.parse(
      json['created_at'] as String?,
      timeZone,
    );
    if (createdAt == null) {
      throw const FormatException('Invalid invoice creation timestamp');
    }
    final totalValue = json['total'];
    if (totalValue is! num || !totalValue.isFinite || totalValue < 0) {
      throw const FormatException('Invalid invoice total');
    }
    return InvoiceRecord(
      id: json['id'] as String,
      number: (json['number'] as num).toInt(),
      total: totalValue.toDouble(),
      isSessionInvoice: json['session_id'] != null,
      createdAt: createdAt,
    );
  }
}
