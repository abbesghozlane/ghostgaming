import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/utils/venue_time_zone.dart';

class AuditLogRepository {
  AuditLogRepository(this._client);

  final SupabaseClient _client;

  Future<List<AuditLogEntry>> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    if (venue.role != 'owner') {
      throw const AuditLogException(
        'Seul le propriétaire peut consulter ce journal.',
      );
    }

    final rows =
        (await _client
                .from('audit_logs')
                .select(
                  'id, actor_id, action, entity_type, entity_id, metadata, created_at',
                )
                .eq('venue_id', venue.id)
                .order('created_at', ascending: false)
                .limit(100))
            .cast<Map<String, dynamic>>();
    return rows
        .map((row) => AuditLogEntry.fromJson(row, venue.timeZone))
        .toList(growable: false);
  }
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.actorId,
    required this.metadata,
    required this.createdAt,
  });

  final int id;
  final String action;
  final String entityType;
  final String? entityId;
  final String? actorId;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  factory AuditLogEntry.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) => AuditLogEntry(
    id: (json['id'] as num).toInt(),
    action: json['action'] as String? ?? 'unknown',
    entityType: json['entity_type'] as String? ?? 'unknown',
    entityId: json['entity_id'] as String?,
    actorId: json['actor_id'] as String?,
    metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    createdAt: VenueTimeZone.parse(json['created_at'] as String?, timeZone),
  );
}

class AuditLogException implements Exception {
  const AuditLogException(this.message);

  final String message;
}

String auditActionLabel(String action) => switch (action) {
  'session_start' => 'Session démarrée',
  'session_end' => 'Session terminée',
  'session_cancel' => 'Session annulée',
  'session_transfer' => 'Session transférée',
  'match_added' => 'Match ajouté',
  'time_added' => 'Temps ajouté',
  'payment_created' => 'Paiement enregistré',
  'product_sale' => 'Vente au comptoir',
  'product_added' => 'Produit ajouté à une session',
  'inventory_adjustment' => 'Stock ajusté',
  'customer_product_ordered' => 'Commande client',
  'employee_invited' => 'Invitation employé créée',
  'employee_joined' => 'Employé ajouté à l’équipe',
  'employee_permissions_changed' => 'Autorisations modifiées',
  'employee_activated' => 'Employé activé',
  'employee_deactivated' => 'Employé désactivé',
  'employee_invitation_cancelled' => 'Invitation annulée',
  _ =>
    action
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' '),
};
