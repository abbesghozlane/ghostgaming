import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/utils/venue_time_zone.dart';

const employeePermissions = <String, String>{
  'manage_stock': 'Gérer le stock',
  'view_reports': 'Consulter les rapports',
  'give_discount': 'Accorder des remises',
  'cancel_session': 'Annuler une session',
  'refund': 'Effectuer un remboursement',
  'edit_prices': 'Modifier les tarifs',
  'manage_credit': 'Gérer les crédits',
};

class EmployeeRepository {
  EmployeeRepository(this._client);

  final SupabaseClient _client;

  Future<EmployeeManagementSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    if (venue.role != 'owner') {
      throw const EmployeeManagementException(
        'Seul le propriétaire peut gérer les employés.',
      );
    }

    final rows = (await _client.rpc(
      'list_venue_staff',
    )).cast<Map<String, dynamic>>();
    final members = rows
        .map((row) => EmployeeMember.fromJson(row, venue.timeZone))
        .toList(growable: false);
    final invitations =
        (await _client
                .from('staff_invitations')
                .select(
                  'id, email, permissions, expires_at, accepted_at, cancelled_at, created_at',
                )
                .eq('venue_id', venue.id)
                .isFilter('accepted_at', null)
                .isFilter('cancelled_at', null)
                .order('created_at', ascending: false))
            .cast<Map<String, dynamic>>();

    return EmployeeManagementSnapshot(
      venue: venue,
      employees: members,
      invitations: invitations
          .map((row) => EmployeeInvitation.fromJson(row, venue.timeZone))
          .toList(growable: false),
    );
  }

  Future<Map<String, dynamic>> createInvitation({
    required String email,
    required Map<String, bool> permissions,
  }) async {
    final result = await _client.rpc(
      'create_staff_invitation',
      params: {'p_email': email.trim(), 'p_permissions': permissions},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> updatePermissions(
    String userId,
    Map<String, bool> permissions,
  ) async {
    await _client.rpc(
      'set_employee_permissions',
      params: {'p_user': userId, 'p_permissions': permissions},
    );
  }

  Future<void> setActive(String userId, bool active) async {
    await _client.rpc(
      'set_employee_active',
      params: {'p_user': userId, 'p_is_active': active},
    );
  }

  Future<void> cancelInvitation(String invitationId) async {
    await _client.rpc(
      'cancel_staff_invitation',
      params: {'p_invitation': invitationId},
    );
  }

  Future<String> acceptInvitation(String token) async {
    final result = await _client.rpc(
      'accept_staff_invitation',
      params: {'p_token': token.trim()},
    );
    final data = Map<String, dynamic>.from(result as Map);
    return data['venue_id'] as String;
  }

  Future<bool> signUpInvitedEmployee({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );
    return response.session != null;
  }
}

class EmployeeManagementSnapshot {
  const EmployeeManagementSnapshot({
    required this.venue,
    required this.employees,
    required this.invitations,
  });

  final VenueContext venue;
  final List<EmployeeMember> employees;
  final List<EmployeeInvitation> invitations;
}

class EmployeeMember {
  const EmployeeMember({
    required this.userId,
    required this.role,
    required this.isActive,
    required this.permissions,
    required this.createdAt,
    required this.email,
    this.name,
    this.phone,
  });

  final String userId;
  final String role;
  final bool isActive;
  final Map<String, bool> permissions;
  final DateTime? createdAt;
  final String email;
  final String? name;
  final String? phone;

  factory EmployeeMember.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) => EmployeeMember(
    userId: json['user_id'] as String,
    role: json['role'] as String? ?? 'employee',
    isActive: json['is_active'] as bool? ?? false,
    permissions: _permissions(json['permissions']),
    createdAt: VenueTimeZone.parse(json['created_at'] as String?, timeZone),
    email: json['email'] as String? ?? '',
    name: json['full_name'] as String?,
    phone: json['phone'] as String?,
  );
}

class EmployeeInvitation {
  const EmployeeInvitation({
    required this.id,
    required this.email,
    required this.permissions,
    required this.expiresAt,
  });

  final String id;
  final String email;
  final Map<String, bool> permissions;
  final DateTime? expiresAt;

  factory EmployeeInvitation.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) =>
      EmployeeInvitation(
        id: json['id'] as String,
        email: json['email'] as String,
        permissions: _permissions(json['permissions']),
        expiresAt: VenueTimeZone.parse(
          json['expires_at'] as String?,
          timeZone,
        ),
      );
}

class EmployeeManagementException implements Exception {
  const EmployeeManagementException(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, bool> _permissions(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String &&
          employeePermissions.containsKey(entry.key) &&
          entry.value is bool)
        entry.key as String: entry.value as bool,
  };
}
