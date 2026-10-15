import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';
import '../../../core/utils/venue_time_zone.dart';

class CashShiftRepository {
  CashShiftRepository(this._client);

  final SupabaseClient _client;

  Future<CashShiftSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    final shifts =
        (await _client
                .from('shifts')
                .select(
                  'id, employee_id, status, opening_cash, expected_cash, '
                  'closing_cash, difference, opened_at, closed_at',
                )
                .eq('venue_id', venue.id)
                .order('opened_at', ascending: false)
                .limit(100))
            .cast<Map<String, dynamic>>();
    final ids = shifts.map((shift) => shift['id'] as String).toList();
    final transactions = ids.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('shift_transactions')
                  .select('id, shift_id, amount, kind, description, created_at')
                  .inFilter('shift_id', ids)
                  .order('created_at', ascending: false))
              .cast<Map<String, dynamic>>();
    final transactionsByShift = <String, List<CashShiftTransaction>>{};
    for (final row in transactions) {
      final item = CashShiftTransaction.fromJson(row, venue.timeZone);
      transactionsByShift.putIfAbsent(item.shiftId, () => []).add(item);
    }
    final items = shifts
        .map(
          (row) => CashShift.fromJson(
            row,
            transactionsByShift[row['id'] as String] ?? const [],
            venue.timeZone,
          ),
        )
        .toList(growable: false);
    final currentUserId = _client.auth.currentUser?.id;
    return CashShiftSnapshot(
      venue: venue,
      shifts: items,
      currentShift: items.cast<CashShift?>().firstWhere(
        (shift) =>
            shift?.status == 'open' && shift?.employeeId == currentUserId,
        orElse: () => null,
      ),
      canManage: venue.role == 'owner' || venue.role == 'manager',
    );
  }

  Future<void> open({required double openingCash}) async {
    await executeIdempotentRpc<void>(_client, 'open_cash_shift', {
      'p_op': OperationId.create(),
      'p_opening_cash': openingCash,
    });
  }

  Future<void> close({
    required String shiftId,
    required double closingCash,
  }) async {
    await executeIdempotentRpc<void>(_client, 'close_cash_shift', {
      'p_op': OperationId.create(),
      'p_shift': shiftId,
      'p_closing_cash': closingCash,
    });
  }
}

class CashShiftSnapshot {
  const CashShiftSnapshot({
    required this.venue,
    required this.shifts,
    required this.currentShift,
    required this.canManage,
  });

  final VenueContext venue;
  final List<CashShift> shifts;
  final CashShift? currentShift;
  final bool canManage;
}

class CashShift {
  const CashShift({
    required this.id,
    required this.employeeId,
    required this.status,
    required this.openingCash,
    required this.expectedCash,
    required this.closingCash,
    required this.difference,
    required this.openedAt,
    required this.closedAt,
    required this.transactions,
  });

  final String id;
  final String employeeId;
  final String status;
  final double openingCash;
  final double? expectedCash;
  final double? closingCash;
  final double? difference;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final List<CashShiftTransaction> transactions;

  double get liveExpectedCash =>
      openingCash +
      transactions.fold<double>(
        0,
        (total, transaction) => total + transaction.amount,
      );

  factory CashShift.fromJson(
    Map<String, dynamic> json,
    List<CashShiftTransaction> transactions, [
    String timeZone = 'Africa/Algiers',
  ]) => CashShift(
    id: json['id'] as String,
    employeeId: json['employee_id'] as String,
    status: json['status'] as String? ?? 'closed',
    openingCash: (json['opening_cash'] as num).toDouble(),
    expectedCash: (json['expected_cash'] as num?)?.toDouble(),
    closingCash: (json['closing_cash'] as num?)?.toDouble(),
    difference: (json['difference'] as num?)?.toDouble(),
    openedAt: VenueTimeZone.parse(json['opened_at'] as String?, timeZone),
    closedAt: VenueTimeZone.parse(json['closed_at'] as String?, timeZone),
    transactions: transactions,
  );
}

class CashShiftTransaction {
  const CashShiftTransaction({
    required this.id,
    required this.shiftId,
    required this.amount,
    required this.kind,
    required this.description,
    required this.createdAt,
  });

  final int id;
  final String shiftId;
  final double amount;
  final String kind;
  final String description;
  final DateTime? createdAt;

  factory CashShiftTransaction.fromJson(
    Map<String, dynamic> json,
    String timeZone,
  ) => CashShiftTransaction(
    id: (json['id'] as num).toInt(),
    shiftId: json['shift_id'] as String,
    amount: (json['amount'] as num).toDouble(),
    kind: json['kind'] as String? ?? 'cash_payment',
    description: json['description'] as String? ?? '',
    createdAt: VenueTimeZone.parse(json['created_at'] as String?, timeZone),
  );
}

String cashShiftErrorMessage(String message) {
  final code = message.toUpperCase();
  if (code.contains('SHIFT_ALREADY_OPEN') || code.contains('23505')) {
    return 'Vous avez déjà une caisse ouverte.';
  }
  if (code.contains('INVALID_OPENING_CASH')) {
    return 'Le fond de caisse doit être positif ou nul.';
  }
  if (code.contains('INVALID_CLOSING_CASH')) {
    return 'Saisissez le montant compté dans la caisse.';
  }
  if (code.contains('SHIFT_NOT_OPEN')) {
    return 'Cette caisse est déjà clôturée.';
  }
  if (code.contains('SHIFT_NOT_FOUND')) {
    return 'Cette caisse est introuvable.';
  }
  if (code.contains('FORBIDDEN') || code.contains('42501')) {
    return 'Votre compte ne peut pas effectuer cette opération.';
  }
  return 'La caisse n’a pas pu être mise à jour. Vérifiez votre connexion.';
}
