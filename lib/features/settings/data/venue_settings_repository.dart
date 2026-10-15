import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';

class VenueSettingsRepository {
  VenueSettingsRepository(this._client);

  final SupabaseClient _client;

  static const timeZones = <String, String>{
    'Africa/Algiers': 'Alger (UTC+1)',
    'Africa/Casablanca': 'Casablanca',
    'Europe/Paris': 'Paris',
    'Europe/London': 'Londres',
    'Asia/Dubai': 'Dubaï',
  };

  Future<VenueSettings> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    if (venue.role != 'owner') {
      throw const VenueSettingsException('FORBIDDEN');
    }
    final row = await _client
        .from('venues')
        .select('id, name, timezone, currency')
        .eq('id', venue.id)
        .single();
    return VenueSettings(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      timeZone: row['timezone'] as String? ?? 'Africa/Algiers',
      currency: row['currency'] as String? ?? 'DA',
    );
  }

  Future<void> save({
    required String venueId,
    required String name,
    required String timeZone,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 100) {
      throw const VenueSettingsException('INVALID_VENUE_NAME');
    }
    if (timeZone.trim().isEmpty || timeZone.trim().length > 64) {
      throw const VenueSettingsException('INVALID_TIMEZONE');
    }
    await _client
        .from('venues')
        .update({'name': cleanName, 'timezone': timeZone})
        .eq('id', venueId);
  }
}

class VenueSettings {
  const VenueSettings({
    required this.id,
    required this.name,
    required this.timeZone,
    required this.currency,
  });

  final String id;
  final String name;
  final String timeZone;
  final String currency;
}

class VenueSettingsException implements Exception {
  const VenueSettingsException(this.code);

  final String code;
}
