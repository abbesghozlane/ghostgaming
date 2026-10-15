import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/cash/data/cash_shift_repository.dart';

void main() {
  test(
    'shift expected cash includes opening float and signed transactions',
    () {
      final shift = CashShift.fromJson(
        {
          'id': 'shift-id',
          'employee_id': 'employee-id',
          'status': 'open',
          'opening_cash': 5000,
          'opened_at': '2026-10-04T10:00:00Z',
        },
        [
          CashShiftTransaction(
            id: 1,
            shiftId: 'shift-id',
            amount: 2000,
            kind: 'cash_payment',
            description: 'Paiement espèces',
            createdAt: DateTime.utc(2026, 10, 4, 11),
          ),
          CashShiftTransaction(
            id: 2,
            shiftId: 'shift-id',
            amount: -500,
            kind: 'expense',
            description: 'Dépense',
            createdAt: DateTime.utc(2026, 10, 4, 12),
          ),
        ],
      );

      expect(shift.liveExpectedCash, 6500);
      expect(shift.transactions.length, 2);
    },
  );

  test('shift workflow translates database errors into French messages', () {
    expect(
      cashShiftErrorMessage('SHIFT_ALREADY_OPEN'),
      contains('déjà une caisse ouverte'),
    );
    expect(
      cashShiftErrorMessage('INVALID_CLOSING_CASH'),
      contains('montant compté'),
    );
  });
}
