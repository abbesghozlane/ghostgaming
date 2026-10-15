import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';
import '../../../core/utils/venue_time_zone.dart';

const expenseCategories = <String, String>{
  'rent': 'Loyer',
  'utilities': 'Électricité et eau',
  'supplies': 'Achats et fournitures',
  'maintenance': 'Entretien',
  'payroll': 'Salaires',
  'other': 'Autre',
};

class ExpenseRepository {
  ExpenseRepository(this._client);

  final SupabaseClient _client;

  Future<ExpenseSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    if (venue.role != 'owner' && venue.role != 'manager') {
      throw const ExpenseException(
        'Seul le propriétaire ou le gérant peut consulter les dépenses.',
      );
    }
    final rows =
        (await _client
                .from('expenses')
                .select(
                  'id, category, description, amount, incurred_at, created_at',
                )
                .eq('venue_id', venue.id)
                .order('incurred_at', ascending: false)
                .limit(200))
            .cast<Map<String, dynamic>>();
    return ExpenseSnapshot(
      venue: venue,
      expenses: rows
          .map((row) => ExpenseItem.fromJson(row, venue.timeZone))
          .toList(growable: false),
    );
  }

  Future<void> create({
    required String category,
    required String description,
    required double amount,
    required DateTime incurredAt,
    required String timeZone,
  }) async {
    await executeIdempotentRpc<void>(_client, 'create_expense', {
      'p_op': OperationId.create(),
      'p_category': category,
      'p_description': description.trim(),
      'p_amount': amount,
      'p_incurred_at': VenueTimeZone.toUtc(
        incurredAt,
        timeZone,
      ).toIso8601String(),
    });
  }
}

class ExpenseSnapshot {
  const ExpenseSnapshot({required this.venue, required this.expenses});

  final VenueContext venue;
  final List<ExpenseItem> expenses;

  double totalFor(DateTime month) => expenses
      .where((expense) {
        final incurredAt = expense.incurredAt;
        return incurredAt != null &&
            incurredAt.year == month.year &&
            incurredAt.month == month.month;
      })
      .fold(0, (total, expense) => total + expense.amount);
}

class ExpenseItem {
  const ExpenseItem({
    required this.id,
    required this.category,
    required this.description,
    required this.amount,
    required this.incurredAt,
  });

  final String id;
  final String category;
  final String description;
  final double amount;
  final DateTime? incurredAt;

  factory ExpenseItem.fromJson(
    Map<String, dynamic> json, [
    String timeZone = 'Africa/Algiers',
  ]) => ExpenseItem(
    id: json['id'] as String,
    category: json['category'] as String? ?? 'other',
    description: json['description'] as String? ?? '',
    amount: (json['amount'] as num).toDouble(),
    incurredAt: VenueTimeZone.parse(json['incurred_at'] as String?, timeZone),
  );
}

class ExpenseException implements Exception {
  const ExpenseException(this.message);

  final String message;
}

String expenseErrorMessage(String message) {
  final code = message.toUpperCase();
  if (code.contains('INVALID_EXPENSE_CATEGORY')) {
    return 'Choisissez une catégorie valide.';
  }
  if (code.contains('INVALID_EXPENSE_DESCRIPTION')) {
    return 'La description doit contenir entre 2 et 500 caractères.';
  }
  if (code.contains('INVALID_EXPENSE_AMOUNT')) {
    return 'Saisissez un montant supérieur à zéro.';
  }
  if (code.contains('INVALID_EXPENSE_DATE')) {
    return 'La date de dépense ne peut pas être dans le futur.';
  }
  if (code.contains('FORBIDDEN') || code.contains('42501')) {
    return 'Votre rôle ne permet pas de gérer les dépenses.';
  }
  return 'La dépense n’a pas pu être enregistrée. Vérifiez votre connexion.';
}
