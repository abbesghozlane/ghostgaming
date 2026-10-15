import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';

class ArchiveRepository {
  ArchiveRepository(this._client);

  final SupabaseClient _client;

  /// Fetches all transactional historical records for the current venue and packages
  /// them into a formatted JSON string for download/backup.
  Future<String> exportArchiveJson() async {
    final venue = await VenueRepository(_client).currentVenue();
    final venueId = venue.id;

    final results = await Future.wait([
      _client.from('sessions').select('*').eq('venue_id', venueId),
      _client.from('orders').select('*').eq('venue_id', venueId),
      _client.from('invoices').select('*').eq('venue_id', venueId),
      _client.from('payments').select('*').eq('venue_id', venueId),
      _client.from('expenses').select('*').eq('venue_id', venueId),
      _client.from('shifts').select('*').eq('venue_id', venueId),
      _client.from('reservations').select('*').eq('venue_id', venueId),
      _client.from('inventory_movements').select('*').eq('venue_id', venueId),
      _client.from('audit_logs').select('*').eq('venue_id', venueId),
    ]);

    final archiveData = {
      'metadata': {
        'venue_id': venue.id,
        'venue_name': venue.name,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'app_version': '1.0.0',
      },
      'sessions': results[0],
      'orders': results[1],
      'invoices': results[2],
      'payments': results[3],
      'expenses': results[4],
      'shifts': results[5],
      'reservations': results[6],
      'inventory_movements': results[7],
      'audit_logs': results[8],
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(archiveData);
  }

  /// Executes atomic reset RPC in Supabase to purge historical data while keeping master records.
  Future<void> resetVenueData() async {
    final venue = await VenueRepository(_client).currentVenue();
    if (venue.role != 'owner' && venue.role != 'manager') {
      throw const PostgrestException(message: 'FORBIDDEN');
    }

    await executeIdempotentRpc<void>(_client, 'archive_and_reset_venue_data', {
      'p_op': OperationId.create(),
      'p_venue_id': venue.id,
    });
  }
}
