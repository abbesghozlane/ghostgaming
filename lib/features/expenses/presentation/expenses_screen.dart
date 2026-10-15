import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/utils/venue_time_zone.dart';
import '../data/expense_repository.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final ExpenseRepository _repository;
  ExpenseSnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = ExpenseRepository(Supabase.instance.client);
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
      final venueChanged = _snapshot?.venue.id != snapshot.venue.id;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
      if (venueChanged) _subscribe(snapshot.venue.id);
    } on ExpenseException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } on PostgrestException catch (error) {
      debugPrint('Chargement des dépenses impossible : $error');
      if (mounted) {
        setState(() {
          _error = expenseErrorMessage(error.message);
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des dépenses impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les dépenses n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    }
  }

  void _subscribe(String venueId) {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client.channel(
      'venue:$venueId:expenses',
      opts: const RealtimeChannelConfig(private: true),
    )..onBroadcast(event: 'INSERT', callback: (_) => _scheduleReload());
    _channel!.subscribe((status, error) {
      if ((status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) &&
          mounted) {
        setState(
          () => _error =
              'La synchronisation des dépenses est interrompue. Actualisez pour réessayer.',
        );
      }
    });
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _addExpense() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final input = await showDialog<_ExpenseInput>(
      context: context,
      builder: (context) => _ExpenseDialog(timeZone: snapshot.venue.timeZone),
    );
    if (input == null || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.create(
        category: input.category,
        description: input.description,
        amount: input.amount,
        incurredAt: input.incurredAt,
        timeZone: snapshot.venue.timeZone,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dépense enregistrée.')));
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = expenseErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Création de la dépense impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La dépense n’a pas été enregistrée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final now = snapshot == null
        ? DateTime.now()
        : VenueTimeZone.now(snapshot.venue.timeZone);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
            children: [
              AppPageHeader(onBack: () => context.pop()),
              const SizedBox(height: 18),
              AppScreenTitle(
                title: 'Dépenses',
                subtitle: snapshot?.venue.name ?? 'Suivi des sorties de caisse',
                trailing: IconButton(
                  tooltip: 'Ajouter une dépense',
                  onPressed: _working ? null : _addExpense,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ExpenseNotice(message: _error!, isError: true),
              ],
              if (_loading && snapshot == null)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot != null) ...[
                const SizedBox(height: 18),
                AppSurface(
                  isSelected: true,
                  borderRadius: 22,
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.red.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.trending_down_rounded,
                          color: AppColors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total ce mois',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${snapshot.totalFor(now).toStringAsFixed(2)} DA',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${snapshot.expenses.where((e) => e.incurredAt?.year == now.year && e.incurredAt?.month == now.month).length} opérations',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Historique',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '200 dernières opérations',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (snapshot.expenses.isEmpty)
                  const _ExpenseNotice(
                    message: 'Aucune dépense enregistrée pour le moment.',
                  )
                else
                  for (final expense in snapshot.expenses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _ExpenseCard(expense: expense),
                    ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: snapshot == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _working ? null : _addExpense,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
              backgroundColor: AppColors.primary,
            ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({required this.expense});

  final ExpenseItem expense;

  @override
  Widget build(BuildContext context) {
    final date = expense.incurredAt;
    final dateText = date == null
        ? 'Date inconnue'
        : DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR').format(date);
    return AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              _categoryIcon(expense.category),
              color: AppColors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${expenseCategories[expense.category] ?? 'Autre'} · $dateText',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '-${expense.amount.toStringAsFixed(2)} DA',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.red,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({required this.timeZone});

  final String timeZone;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'other';
  late DateTime _date = VenueTimeZone.now(widget.timeZone);
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final now = VenueTimeZone.now(widget.timeZone);
    final result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: VenueTimeZone.dateTime(
        widget.timeZone,
        year: now.year - 10,
        month: now.month,
      ),
      lastDate: now,
      helpText: 'Date de la dépense',
    );
    if (result != null) {
      setState(
        () => _date = VenueTimeZone.dateTime(
          widget.timeZone,
          year: result.year,
          month: result.month,
          day: result.day,
          hour: _date.hour,
          minute: _date.minute,
        ),
      );
    }
  }

  void _submit() {
    final description = _description.text.trim();
    final normalizedAmount = _amount.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(normalizedAmount);
    if (description.length < 2 ||
        description.length > 500 ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0) {
      setState(
        () => _error =
            'Saisissez une description et un montant supérieur à zéro.',
      );
      return;
    }
    Navigator.pop(
      context,
      _ExpenseInput(
        category: _category,
        description: description,
        amount: amount,
        incurredAt: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvelle dépense'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Catégorie'),
            items: [
              for (final entry in expenseCategories.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Ex. facture d’électricité',
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Montant',
              suffixText: 'DA',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(DateFormat('dd MMMM yyyy', 'fr_FR').format(_date)),
            ),
          ),
          if (_error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 11, color: AppColors.red),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
    ],
  );
}

class _ExpenseInput {
  const _ExpenseInput({
    required this.category,
    required this.description,
    required this.amount,
    required this.incurredAt,
  });

  final String category;
  final String description;
  final double amount;
  final DateTime incurredAt;
}

class _ExpenseNotice extends StatelessWidget {
  const _ExpenseNotice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    child: Text(
      message,
      style: TextStyle(
        fontSize: 12,
        color: isError ? AppColors.red : AppColors.muted,
      ),
    ),
  );
}

IconData _categoryIcon(String category) => switch (category) {
  'rent' => Icons.home_work_outlined,
  'utilities' => Icons.bolt_rounded,
  'supplies' => Icons.shopping_bag_outlined,
  'maintenance' => Icons.build_outlined,
  'payroll' => Icons.groups_outlined,
  _ => Icons.receipt_long_outlined,
};
