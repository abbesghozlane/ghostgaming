import 'package:supabase_flutter/supabase_flutter.dart';
import 'current_role_cache.dart';

class VenueContext {
  const VenueContext({
    required this.id,
    required this.name,
    required this.role,
    required this.permissions,
    this.timeZone = 'Africa/Algiers',
  });

  final String id;
  final String name;
  final String role;
  final Map<String, dynamic> permissions;
  final String timeZone;

  bool get canManageCatalog => role == 'owner' || role == 'manager';
  bool get canManageStock => switch (role) {
    'owner' => true,
    'manager' => permissions['manage_stock'] != false,
    'employee' => permissions['manage_stock'] == true,
    _ => false,
  };
  bool get canManageCredit =>
      role == 'owner' ||
      role == 'manager' ||
      (role == 'employee' && permissions['manage_credit'] == true);
  bool get canGiveDiscount =>
      role == 'owner' ||
      (role == 'manager' && permissions['give_discount'] != false) ||
      (role == 'employee' && permissions['give_discount'] == true);
}

class VenueRepository {
  VenueRepository(this._client);

  final SupabaseClient _client;

  Future<VenueContext> currentVenue() async {
    final user = _client.auth.currentUser;
    if (user == null) throw const VenueRepositoryException('UNAUTHENTICATED');

    final membership = await _client
        .from('venue_members')
        .select('venue_id, role, permissions')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .order('created_at')
        .limit(1)
        .maybeSingle();

    if (membership == null) {
      final customer = await _client
          .from('customers')
          .select('venue_id')
          .eq('user_id', user.id)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      if (customer != null && customer['venue_id'] != null) {
        final venueId = customer['venue_id'] as String;
        final venue = await _client
            .from('venues')
            .select('name, timezone')
            .eq('id', venueId)
            .single();
        CurrentRoleCache.setRole('customer');
        return VenueContext(
          id: venueId,
          name: venue['name'] as String? ?? 'Ma salle',
          role: 'customer',
          timeZone: venue['timezone'] as String? ?? 'Africa/Algiers',
          permissions: const {},
        );
      }
      throw const VenueRepositoryException('VENUE_NOT_FOUND');
    }

    final venueId = membership['venue_id'] as String;
    final venue = await _client
        .from('venues')
        .select('name, timezone')
        .eq('id', venueId)
        .single();
    final role = membership['role'] as String? ?? 'customer';
    CurrentRoleCache.setRole(role);
    return VenueContext(
      id: venueId,
      name: venue['name'] as String? ?? 'Ma salle',
      role: role,
      timeZone: venue['timezone'] as String? ?? 'Africa/Algiers',
      permissions: Map<String, dynamic>.from(
        membership['permissions'] as Map? ?? const {},
      ),
    );
  }
}

class VenueRepositoryException implements Exception {
  const VenueRepositoryException(this.code);

  final String code;
}
