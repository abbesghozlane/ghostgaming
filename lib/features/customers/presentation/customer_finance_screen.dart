import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/customer_finance_repository.dart';

class CustomerFinanceScreen extends StatefulWidget {
  const CustomerFinanceScreen({super.key});

  @override
  State<CustomerFinanceScreen> createState() => _CustomerFinanceScreenState();
}

class _CustomerFinanceScreenState extends State<CustomerFinanceScreen> {
  late final CustomerFinanceRepository _repository;
  CustomerFinanceSnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = CustomerFinanceRepository(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _reloadTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _repository.load();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
      final venueId = snapshot.venue.id;
      if (_channel == null) _subscribe(venueId);
    } on PostgrestException catch (error) {
      debugPrint('Chargement des comptes clients impossible : $error');
      if (mounted) {
        setState(() {
          _error = customerFinanceErrorMessage(error.message);
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des comptes clients impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les comptes clients n’ont pas pu être chargés.';
          _loading = false;
        });
      }
    }
  }

  void _subscribe(String venueId) {
    _channel = Supabase.instance.client.channel(
      'venue:$venueId:customers',
      opts: const RealtimeChannelConfig(private: true),
    )..onBroadcast(event: 'INSERT', callback: (_) => _scheduleReload());
    for (final event in ['UPDATE', 'DELETE']) {
      _channel!.onBroadcast(event: event, callback: (_) => _scheduleReload());
    }
    _channel!.subscribe((status, error) {
      if ((status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) &&
          mounted) {
        setState(
          () => _error =
              'La synchronisation des comptes est interrompue. Actualisez pour réessayer.',
        );
      }
    });
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _operate(
    CustomerFinanceAccount customer,
    _FinanceOperation operation,
  ) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.operate(
        customerId: customer.id,
        action: operation.action,
        amount: operation.amount,
        method: operation.method,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opération enregistrée.')),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = customerFinanceErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Opération sur le compte client impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'L’opération n’a pas pu être enregistrée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _startOperation(
    CustomerFinanceAccount customer,
    String action,
  ) async {
    final operation = await showDialog<_FinanceOperation>(
      context: context,
      builder: (context) => _CustomerFinanceDialog(
        customer: customer,
        action: action,
      ),
    );
    if (operation != null && mounted) await _operate(customer, operation);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
            children: [
              AppScreenTitle(
                title: 'Comptes clients & Dettes',
                subtitle: 'Suivi des crédits et statuts des impayés',
                trailing: IconButton(
                  tooltip: 'Retour',
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/admin');
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AppSurface(
                  borderRadius: 16,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
              ],
              if (_loading && snapshot == null)
                const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot?.customers.isEmpty ?? true)
                const Padding(
                  padding: EdgeInsets.only(top: 28),
                  child: AppSurface(
                    borderRadius: 20,
                    child: Text(
                      'Aucun client enregistré dans cette salle.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...snapshot!.customers.map(_customerCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customerCard(CustomerFinanceAccount customer) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: AppSurface(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (customer.phone != null) ...[
            const SizedBox(height: 3),
            Text(
              customer.phone!,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BalanceValue(
                  label: 'Portefeuille',
                  value: customer.walletBalance,
                  color: AppColors.green,
                ),
              ),
              Expanded(
                child: _BalanceValue(
                  label: 'Crédit utilisé',
                  value: customer.creditBalance,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Limite disponible : ${customer.availableCredit.toStringAsFixed(2)} DA',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          if (customer.ledgerEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text(
              'Dettes & Mouvements en cours',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...customer.ledgerEntries.take(6).map((entry) {
              final reason = entry['reason'] as String? ?? '';
              final delta = (entry['delta'] as num?)?.toDouble() ?? 0;
              final isDebt = reason == 'debt_created';
              final label = isDebt ? 'Création de dette' : reason == 'credit_repayment' ? 'Remboursement' : 'Rechargement';
              final statusLabel = isDebt ? 'Non payé (En cours)' : 'Payé';
              final statusColor = isDebt ? AppColors.amber : AppColors.green;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        Text(statusLabel, style: TextStyle(fontSize: 10.5, color: statusColor, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Text(
                      '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)} DA',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: delta > 0 ? AppColors.amber : AppColors.green),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionButton(
                label: 'Recharger',
                onPressed: _working
                    ? null
                    : () => _startOperation(customer, 'wallet_top_up'),
              ),
              if (_snapshot?.canManageCredit == true) ...[
                _ActionButton(
                  label: 'Rembourser le crédit',
                  onPressed: _working || customer.creditBalance <= 0
                      ? null
                      : () => _startOperation(customer, 'credit_repayment'),
                ),
                _ActionButton(
                  label: 'Modifier la limite',
                  onPressed: _working
                      ? null
                      : () => _startOperation(customer, 'set_credit_limit'),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _BalanceValue extends StatelessWidget {
  const _BalanceValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      const SizedBox(height: 3),
      Text(
        '${value.toStringAsFixed(2)} DA',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
      ),
    ],
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    child: Text(label),
  );
}

class _FinanceOperation {
  const _FinanceOperation(this.action, this.amount, {this.method});

  final String action;
  final double amount;
  final String? method;
}

class _CustomerFinanceDialog extends StatefulWidget {
  const _CustomerFinanceDialog({required this.customer, required this.action});

  final CustomerFinanceAccount customer;
  final String action;

  @override
  State<_CustomerFinanceDialog> createState() => _CustomerFinanceDialogState();
}

class _CustomerFinanceDialogState extends State<_CustomerFinanceDialog> {
  late final _amount = TextEditingController(
    text: widget.action == 'set_credit_limit'
        ? widget.customer.creditLimit.toStringAsFixed(2)
        : '',
  );
  String _method = 'cash';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLimit = widget.action == 'set_credit_limit';
    final isRepayment = widget.action == 'credit_repayment';
    final title = isLimit
        ? 'Limite de crédit'
        : isRepayment
        ? 'Remboursement du crédit'
        : 'Recharger le portefeuille';
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: isLimit ? 'Nouvelle limite' : 'Montant',
              suffixText: 'DA',
            ),
          ),
          if (!isLimit) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Mode de paiement'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Espèces')),
                DropdownMenuItem(value: 'card', child: Text('Carte')),
              ],
              onChanged: (value) {
                print(value);
                if (value != null) setState(() => _method = value);
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(
              _amount.text.trim().replaceAll(',', '.'),
            );
            if (amount == null || amount < 0 || (!isLimit && amount == 0)) {
              return;
            }
            Navigator.pop(
              context,
              _FinanceOperation(
                widget.action,
                amount,
                method: isLimit ? null : _method,
              ),
            );
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
