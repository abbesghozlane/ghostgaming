import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/utils/venue_time_zone.dart';
import 'package:ghostgaming/features/audit/data/audit_log_repository.dart';

void main() {
  test('audit log entry parses server values and localizes known actions', () {
    final entry = AuditLogEntry.fromJson({
      'id': 42,
      'actor_id': '12345678-1234-1234-1234-123456789abc',
      'action': 'session_start',
      'entity_type': 'session',
      'entity_id': 'abcdef01-1234-1234-1234-123456789abc',
      'metadata': {'game': 'eFootball', 'post': 'Post 01'},
      'created_at': '2026-10-04T12:00:00Z',
    });

    expect(entry.id, 42);
    expect(entry.metadata['game'], 'eFootball');
    expect(
      entry.createdAt,
      VenueTimeZone.parse('2026-10-04T12:00:00Z', 'Africa/Algiers'),
    );
    expect(auditActionLabel(entry.action), 'Session démarrée');
  });

  test('unknown audit actions remain readable', () {
    expect(auditActionLabel('custom_operation'), 'Custom Operation');
  });
}
