import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/utils/venue_time_zone.dart';
import 'package:ghostgaming/features/employees/data/employee_repository.dart';

void main() {
  test('employee permissions preserve disabled values from the server', () {
    final member = EmployeeMember.fromJson({
      'user_id': 'employee-id',
      'email': 'staff@example.com',
      'role': 'employee',
      'is_active': true,
      'permissions': {
        'manage_stock': true,
        'view_reports': false,
        'unknown_permission': true,
      },
      'created_at': '2026-10-04T12:00:00Z',
    });

    expect(member.permissions, {'manage_stock': true, 'view_reports': false});
    expect(member.isActive, isTrue);
  });

  test('invitation expiration is parsed for display', () {
    final invitation = EmployeeInvitation.fromJson({
      'id': 'invitation-id',
      'email': 'staff@example.com',
      'permissions': {},
      'expires_at': '2026-10-11T12:00:00Z',
    });

    expect(
      invitation.expiresAt,
      VenueTimeZone.parse('2026-10-11T12:00:00Z', 'Africa/Algiers'),
    );
  });
}
