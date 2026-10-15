import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';
import '../../../core/utils/venue_time_zone.dart';

class ReservationRepository {
  ReservationRepository(this._client);

  final SupabaseClient _client;

  Future<ReservationSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    final isStaff =
        venue.role == 'owner' ||
        venue.role == 'manager' ||
        venue.role == 'employee';
    final customerRows =
        (isStaff
                ? await _client
                      .from('customers')
                      .select('id, full_name, venue_id')
                      .eq('venue_id', venue.id)
                : await _client
                      .from('customers')
                      .select('id, full_name, venue_id')
                      .eq('user_id', _client.auth.currentUser!.id)
                      .eq('venue_id', venue.id))
            .cast<Map<String, dynamic>>();
    final rows = isStaff
        ? (await _client
                  .from('reservations')
                  .select(
                    'id, venue_id, post_id, customer_id, starts_at, ends_at, status, '
                    'posts(name, device, screen_info), customers(full_name)',
                  )
                  .eq('venue_id', venue.id)
                  .order('starts_at', ascending: false)
                  .limit(100))
              .cast<Map<String, dynamic>>()
        : customerRows.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('reservations')
                  .select(
                    'id, venue_id, post_id, customer_id, starts_at, ends_at, status, '
                    'posts(name, device, screen_info), customers(full_name)',
                  )
                  .inFilter(
                    'customer_id',
                    customerRows.map((customer) => customer['id']).toList(),
                  )
                  .order('starts_at', ascending: false)
                  .limit(100))
              .cast<Map<String, dynamic>>();
    final posts =
        (await _client
                .from('posts')
                .select('id, name, device, screen_info, status')
                .eq('venue_id', venue.id)
                .not('status', 'in', '(maintenance,offline)')
                .order('number'))
            .cast<Map<String, dynamic>>();

    return ReservationSnapshot(
      venue: venue,
      isStaff: isStaff,
      canManage: venue.role == 'owner' || venue.role == 'manager',
      reservations: rows
          .map((row) => ReservationItem.fromJson(row, venue.timeZone))
          .toList(growable: false),
      posts: posts,
      customers: customerRows
          .map(ReservationCustomer.fromJson)
          .toList(growable: false),
      customer: isStaff || customerRows.isEmpty ? null : customerRows.first,
    );
  }

  Future<void> reserve({
    required String postId,
    required DateTime startsAt,
    required int durationMinutes,
    required String timeZone,
  }) async {
    await executeIdempotentRpc<void>(_client, 'reserve_post', {
      'p_op': OperationId.create(),
      'p_post': postId,
      'p_starts_at': VenueTimeZone.toUtc(startsAt, timeZone).toIso8601String(),
      'p_duration_minutes': durationMinutes,
    });
  }

  Future<void> reserveForCustomer({
    required String postId,
    required String customerId,
    required DateTime startsAt,
    required int durationMinutes,
    required String timeZone,
  }) async {
    await executeIdempotentRpc<void>(_client, 'staff_reserve_post', {
      'p_op': OperationId.create(),
      'p_post': postId,
      'p_customer': customerId,
      'p_starts_at': VenueTimeZone.toUtc(startsAt, timeZone).toIso8601String(),
      'p_duration_minutes': durationMinutes,
    });
  }

  Future<ReservationCustomer> createWalkInCustomer({
    required String venueId,
    required String fullName,
    String? phone,
  }) async {
    final row = await _client
        .from('customers')
        .insert({
          'venue_id': venueId,
          'full_name': fullName.trim(),
          'phone': phone == null || phone.trim().isEmpty ? null : phone.trim(),
        })
        .select('id, full_name')
        .single();
    return ReservationCustomer.fromJson(row);
  }

  Future<void> cancel(String reservationId) async {
    await executeIdempotentRpc<void>(_client, 'cancel_reservation', {
      'p_op': OperationId.create(),
      'p_reservation': reservationId,
    });
  }

  Future<void> setStatus(String reservationId, String status) async {
    await executeIdempotentRpc<void>(_client, 'set_reservation_status', {
      'p_op': OperationId.create(),
      'p_reservation': reservationId,
      'p_status': status,
    });
  }
}

class ReservationCustomer {
  const ReservationCustomer({required this.id, required this.name});

  final String id;
  final String name;

  factory ReservationCustomer.fromJson(Map<String, dynamic> json) =>
      ReservationCustomer(
        id: json['id'] as String,
        name: json['full_name'] as String? ?? 'Client',
      );
}

class ReservationSnapshot {
  const ReservationSnapshot({
    required this.venue,
    required this.isStaff,
    required this.canManage,
    required this.reservations,
    required this.posts,
    required this.customers,
    required this.customer,
  });

  final VenueContext venue;
  final bool isStaff;
  final bool canManage;
  final List<ReservationItem> reservations;
  final List<Map<String, dynamic>> posts;
  final List<ReservationCustomer> customers;
  final Map<String, dynamic>? customer;
}

class ReservationItem {
  const ReservationItem({
    required this.id,
    required this.postId,
    required this.customerId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.postName,
    required this.customerName,
  });

  final String id;
  final String postId;
  final String customerId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String status;
  final String postName;
  final String customerName;

  factory ReservationItem.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) {
    final post = json['posts'] as Map<String, dynamic>?;
    final customer = json['customers'] as Map<String, dynamic>?;
    return ReservationItem(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      customerId: json['customer_id'] as String,
      startsAt: VenueTimeZone.parse(json['starts_at'] as String?, timeZone),
      endsAt: VenueTimeZone.parse(json['ends_at'] as String?, timeZone),
      status: json['status'] as String? ?? 'confirmed',
      postName: post?['name'] as String? ?? 'Post',
      customerName: customer?['full_name'] as String? ?? 'Client',
    );
  }
}

String reservationStatusLabel(String status) => switch (status) {
  'confirmed' => 'Confirmée',
  'cancelled' => 'Annulée',
  'completed' => 'Terminée',
  'no_show' => 'Client absent',
  _ => status,
};

String reservationErrorMessage(String message) {
  final code = message.toUpperCase();
  if (code.contains('RESERVATION_SLOT_TAKEN') || code.contains('23P01')) {
    return 'Ce poste vient d’être réservé sur ce créneau. Choisissez un autre horaire.';
  }
  if (code.contains('INVALID_RESERVATION_TIME')) {
    return 'Choisissez un horaire futur dans les 30 prochains jours.';
  }
  if (code.contains('INVALID_RESERVATION_DURATION')) {
    return 'La durée choisie n’est pas valide.';
  }
  if (code.contains('POST_UNAVAILABLE')) {
    return 'Ce poste est indisponible.';
  }
  if (code.contains('POST_NOT_FOUND')) {
    return 'Ce poste n’est plus disponible dans cette salle.';
  }
  if (code.contains('RESERVATION_ALREADY_STARTED')) {
    return 'Une réservation commencée ne peut plus être annulée.';
  }
  if (code.contains('RESERVATION_NOT_CONFIRMED')) {
    return 'Cette réservation n’est plus active.';
  }
  if (code.contains('INVALID_RESERVATION_STATUS')) {
    return 'Ce statut de réservation n’est pas valide.';
  }
  if (code.contains('CUSTOMER_NOT_LINKED')) {
    return 'Liez d’abord votre compte client à une salle.';
  }
  if (code.contains('CUSTOMER_NOT_FOUND')) {
    return 'Le client sélectionné n’existe plus dans cette salle.';
  }
  if (code.contains('23505')) {
    return 'Un client utilise déjà ce numéro de téléphone dans cette salle.';
  }
  if (code.contains('FORBIDDEN') || code.contains('42501')) {
    return 'Votre compte n’est pas autorisé à effectuer cette action.';
  }
  return 'La réservation n’a pas pu être traitée. Vérifiez votre connexion.';
}
