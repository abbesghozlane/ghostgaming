import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';

class CustomerFinanceRepository {
  CustomerFinanceRepository(this._client);

  final SupabaseClient _client;

  Future<CustomerFinanceSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    final results = await Future.wait([
      _client
          .from('customers')
          .select('id, full_name, phone, credit_limit')
          .eq('venue_id', venue.id)
          .order('full_name'),
      _client
          .from('customer_balances')
          .select('customer_id, wallet_balance, credit_balance')
          .eq('venue_id', venue.id),
      _client
          .from('customer_ledger_entries')
          .select('id, customer_id, account, delta, reason, created_at, session_id')
          .eq('venue_id', venue.id)
          .order('created_at', ascending: false),
    ]);
    final balances = {
      for (final row in (results[1] as List).cast<Map<String, dynamic>>())
        row['customer_id'] as String: row,
    };
    final rawLedger = (results[2] as List).cast<Map<String, dynamic>>();
    final ledgerByCustomer = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawLedger) {
      final custId = entry['customer_id'] as String?;
      if (custId != null) {
        ledgerByCustomer.putIfAbsent(custId, () => []).add(entry);
      }
    }

    final customers = (results[0] as List)
        .cast<Map<String, dynamic>>()
        .map((row) {
          final custId = row['id'] as String;
          final balance = balances[custId] ?? const {};
          final ledger = ledgerByCustomer[custId] ?? const [];
          return CustomerFinanceAccount.fromJson({
            ...row,
            ...balance,
            'ledger_entries': ledger,
          });
        })
        .toList(growable: false);

    return CustomerFinanceSnapshot(
      venue: venue,
      customers: customers,
      canManageCredit:
          venue.role == 'owner' ||
          venue.role == 'manager' ||
          venue.permissions['manage_credit'] == true,
    );
  }

  Future<void> operate({
    required String customerId,
    required String action,
    required double amount,
    String? method,
  }) async {
    await executeIdempotentRpc<void>(
      _client,
      'create_customer_financial_operation',
      {
        'p_op': OperationId.create(),
        'p_customer': customerId,
        'p_action': action,
        'p_amount': amount,
        'p_method': method,
      },
    );
  }
}

class CustomerFinanceSnapshot {
  const CustomerFinanceSnapshot({
    required this.venue,
    required this.customers,
    required this.canManageCredit,
  });

  final VenueContext venue;
  final List<CustomerFinanceAccount> customers;
  final bool canManageCredit;
}

class CustomerFinanceAccount {
  const CustomerFinanceAccount({
    required this.id,
    required this.name,
    required this.phone,
    required this.walletBalance,
    required this.creditBalance,
    required this.creditLimit,
    required this.ledgerEntries,
  });

  final String id;
  final String name;
  final String? phone;
  final double walletBalance;
  final double creditBalance;
  final double creditLimit;
  final List<Map<String, dynamic>> ledgerEntries;
  double get availableCredit => creditLimit - creditBalance;

  factory CustomerFinanceAccount.fromJson(Map<String, dynamic> json) =>
      CustomerFinanceAccount(
        id: json['id'] as String? ?? json['customer_id'] as String,
        name: json['full_name'] as String? ?? '',
        phone: json['phone'] as String?,
        walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0,
        creditBalance: (json['credit_balance'] as num?)?.toDouble() ?? 0,
        creditLimit: (json['credit_limit'] as num?)?.toDouble() ?? 0,
        ledgerEntries: (json['ledger_entries'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            const [],
      );
}

String customerFinanceErrorMessage(String message) {
  final code = message.toUpperCase();
  if (code.contains('CUSTOMER_NOT_FOUND')) {
    return 'Ce compte client est introuvable.';
  }
  if (code.contains('REPAYMENT_EXCEEDS_BALANCE')) {
    return 'Le remboursement dépasse le crédit restant.';
  }
  if (code.contains('CREDIT_LIMIT_BELOW_BALANCE')) {
    return 'La limite ne peut pas être inférieure au crédit utilisé.';
  }
  if (code.contains('INVALID_FINANCIAL_AMOUNT')) {
    return 'Saisissez un montant valide.';
  }
  if (code.contains('INVALID_PAYMENT_METHOD')) {
    return 'Choisissez un mode de paiement valide.';
  }
  if (code.contains('CREDIT_LIMIT_EXCEEDED')) {
    return 'La limite de crédit du client serait dépassée.';
  }
  if (code.contains('INSUFFICIENT_WALLET')) {
    return 'Le solde du portefeuille est insuffisant.';
  }
  if (code.contains('CUSTOMER_REQUIRED')) {
    return 'Associez un client à la session pour utiliser son compte.';
  }
  if (code.contains('FORBIDDEN') || code.contains('42501')) {
    return 'Votre compte ne dispose pas de cette autorisation.';
  }
  return 'L’opération financière a échoué. Vérifiez votre connexion.';
}
