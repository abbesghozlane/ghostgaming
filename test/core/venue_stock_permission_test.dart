import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/data/venue_repository.dart';

void main() {
  test('stock management is granted only to authorized staff roles', () {
    const owner = VenueContext(
      id: 'venue',
      name: 'Salle',
      role: 'owner',
      permissions: {},
    );
    const manager = VenueContext(
      id: 'venue',
      name: 'Salle',
      role: 'manager',
      permissions: {},
    );
    const restrictedManager = VenueContext(
      id: 'venue',
      name: 'Salle',
      role: 'manager',
      permissions: {'manage_stock': false},
    );
    const stockEmployee = VenueContext(
      id: 'venue',
      name: 'Salle',
      role: 'employee',
      permissions: {'manage_stock': true},
    );
    const readOnlyEmployee = VenueContext(
      id: 'venue',
      name: 'Salle',
      role: 'employee',
      permissions: {'manage_stock': false},
    );
    const customer = VenueContext(
      id: 'venue',
      name: 'Salle',
      role: 'customer',
      permissions: {'manage_stock': true},
    );

    expect(owner.canManageStock, isTrue);
    expect(manager.canManageStock, isTrue);
    expect(restrictedManager.canManageStock, isFalse);
    expect(stockEmployee.canManageStock, isTrue);
    expect(readOnlyEmployee.canManageStock, isFalse);
    expect(customer.canManageStock, isFalse);
  });
}
