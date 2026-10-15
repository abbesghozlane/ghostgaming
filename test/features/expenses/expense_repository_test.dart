import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/data/venue_repository.dart';
import 'package:ghostgaming/core/utils/venue_time_zone.dart';
import 'package:ghostgaming/features/expenses/data/expense_repository.dart';

void main() {
  test('expense records parse money and local timestamps', () {
    final expense = ExpenseItem.fromJson({
      'id': 'expense-id',
      'category': 'utilities',
      'description': 'Facture d’électricité',
      'amount': 1250.5,
      'incurred_at': '2026-10-04T12:30:00Z',
    });

    expect(expense.category, 'utilities');
    expect(expense.amount, 1250.5);
    expect(
      expense.incurredAt,
      VenueTimeZone.parse('2026-10-04T12:30:00Z', 'Africa/Algiers'),
    );
    expect(expenseCategories[expense.category], 'Électricité et eau');
  });

  test('expense totals aggregate only the selected calendar month', () {
    final snapshot = ExpenseSnapshot(
      venue: const VenueContext(
        id: 'venue-id',
        name: 'Salle',
        role: 'owner',
        permissions: {},
      ),
      expenses: [
        ExpenseItem(
          id: 'one',
          category: 'rent',
          description: 'Loyer',
          amount: 1000,
          incurredAt: DateTime(2026, 10, 1),
        ),
        ExpenseItem(
          id: 'two',
          category: 'utilities',
          description: 'Électricité',
          amount: 250,
          incurredAt: DateTime(2026, 10, 2),
        ),
        ExpenseItem(
          id: 'three',
          category: 'supplies',
          description: 'Achats',
          amount: 99,
          incurredAt: DateTime(2026, 9, 30),
        ),
      ],
    );

    expect(snapshot.totalFor(DateTime(2026, 10)), 1250);
  });

  test('expense backend failures have actionable French messages', () {
    expect(
      expenseErrorMessage('INVALID_EXPENSE_AMOUNT'),
      contains('supérieur à zéro'),
    );
    expect(expenseErrorMessage('FORBIDDEN'), contains('rôle ne permet pas'));
  });
}
