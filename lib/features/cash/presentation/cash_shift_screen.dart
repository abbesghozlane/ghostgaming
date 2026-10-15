import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/cash_shift_repository.dart';

class CashShiftScreen extends StatefulWidget {
  const CashShiftScreen({super.key});

  @override
  State<CashShiftScreen> createState() => _CashShiftScreenState();
}

class _CashShiftScreenState extends State<CashShiftScreen> {
  late final CashShiftRepository _repository;
  CashShiftSnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = CashShiftRepository(Supabase.instance.client);
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
    } on PostgrestException catch (error) {
      debugPrint('Chargement des caisses impossible : $error');
      if (mounted) {
        setState(() {
          _error = cashShiftErrorMessage(error.message);
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des caisses impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les opérations de caisse n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    }
  }

  void _subscribe(String venueId) {
    _channel?.unsubscribe();
    _channel = Supabase.instance.client.channel(
      'venue:$venueId:shifts',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE']) {
      _channel!.onBroadcast(event: event, callback: (_) => _scheduleReload());
    }
    _channel!.subscribe((status, error) {
      if ((status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) &&
          mounted) {
        setState(
          () => _error =
              'La synchronisation de la caisse est interrompue. Actualisez pour réessayer.',
        );
      }
    });
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _openShift() async {
    final amount = await _askForCash(
      title: 'Ouvrir la caisse',
      label: 'Fond de caisse initial',
    );
    if (amount == null || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.open(openingCash: amount);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Votre service de caisse est ouvert.')),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = cashShiftErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Ouverture de caisse impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La caisse n’a pas pu être ouverte.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _closeShift(CashShift shift) async {
    final amount = await _askForCash(
      title: 'Clôturer la caisse',
      label: 'Montant compté en espèces',
      expected: shift.liveExpectedCash,
    );
    if (amount == null || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.close(shiftId: shift.id, closingCash: amount);
      await _load();
      if (mounted) {
        final difference = amount - shift.liveExpectedCash;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              difference.abs() < 0.01
                  ? 'Caisse clôturée. Aucun écart constaté.'
                  : 'Caisse clôturée · Écart : ${difference.toStringAsFixed(2)} DA',
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() => _error = cashShiftErrorMessage(error.message));
      }
    } catch (error, stackTrace) {
      debugPrint('Clôture de caisse impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La caisse n’a pas pu être clôturée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<double?> _askForCash({
    required String title,
    required String label,
    double? expected,
  }) async {
    final controller = TextEditingController(
      text: expected == null ? '' : expected.toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (expected != null) ...[
                Text(
                  'Montant attendu : ${expected.toStringAsFixed(2)} DA',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: label, suffixText: 'DA'),
                validator: (value) {
                  final normalized = value?.trim().replaceAll(',', '.') ?? '';
                  final number = double.tryParse(normalized);
                  if (number == null || !number.isFinite || number < 0) {
                    return 'Saisissez un montant positif ou nul.';
                  }
                  if (number > 1000000000) return 'Montant trop élevé.';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(
                context,
                double.parse(controller.text.trim().replaceAll(',', '.')),
              );
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final currentShift = snapshot?.currentShift;
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
                title: 'Services & Caisse',
                subtitle: snapshot?.venue.name ?? 'Ouverture et clôture',
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _CashNotice(message: _error!, isError: true),
              ],
              if (_loading && snapshot == null)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot != null) ...[
                const SizedBox(height: 18),
                if (currentShift == null)
                  _OpenShiftCard(working: _working, onOpen: _openShift)
                else
                  _ActiveShiftCard(
                    shift: currentShift,
                    working: _working,
                    onClose: () => _closeShift(currentShift),
                  ),
                const SizedBox(height: 22),
                const Text(
                  'Historique des services',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (snapshot.shifts.isEmpty)
                  const _CashNotice(
                    message: 'Aucun service de caisse enregistré.',
                  )
                else
                  for (final shift in snapshot.shifts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _ShiftHistoryCard(shift: shift),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenShiftCard extends StatelessWidget {
  const _OpenShiftCard({required this.working, required this.onOpen});

  final bool working;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppSurface(
    isSelected: true,
    borderRadius: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.point_of_sale_rounded,
          size: 30,
          color: AppColors.pink,
        ),
        const SizedBox(height: 12),
        const Text(
          'Aucun service ouvert',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          'Ouvrez votre caisse avec le montant initial présent dans le tiroir.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: working ? 'Ouverture…' : 'Ouvrir la caisse',
          onPressed: working ? () {} : onOpen,
        ),
      ],
    ),
  );
}

class _ActiveShiftCard extends StatelessWidget {
  const _ActiveShiftCard({
    required this.shift,
    required this.working,
    required this.onClose,
  });

  final CashShift shift;
  final bool working;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => AppSurface(
    isSelected: true,
    borderRadius: 22,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.lock_open_rounded, color: AppColors.green),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Caisse ouverte',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            _ShiftBadge(open: true),
          ],
        ),
        const SizedBox(height: 14),
        _CashValueRow(label: 'Fond de caisse', value: shift.openingCash),
        const SizedBox(height: 8),
        _CashValueRow(
          label: 'Espèces nettes enregistrées',
          value: shift.liveExpectedCash - shift.openingCash,
        ),
        const Divider(height: 22),
        _CashValueRow(
          label: 'Espèces attendues',
          value: shift.liveExpectedCash,
          prominent: true,
        ),
        const SizedBox(height: 4),
        Text(
          '${shift.transactions.length} mouvements · Ouverte ${_formatDate(shift.openedAt)}',
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
        const SizedBox(height: 14),
        AppButton(
          label: working ? 'Clôture…' : 'Compter et clôturer',
          isGhost: true,
          onPressed: working ? () {} : onClose,
        ),
      ],
    ),
  );
}

class _ShiftHistoryCard extends StatelessWidget {
  const _ShiftHistoryCard({required this.shift});

  final CashShift shift;

  @override
  Widget build(BuildContext context) {
    final opened = _formatDate(shift.openedAt);
    final difference = shift.difference;
    return AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.point_of_sale_rounded,
                color: AppColors.primaryLight,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Service du $opened',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ShiftBadge(open: shift.status == 'open'),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Fond : ${shift.openingCash.toStringAsFixed(2)} DA · '
            'Mouvements : ${shift.transactions.length}',
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
          if (shift.status == 'closed') ...[
            const SizedBox(height: 6),
            Text(
              'Attendu : ${(shift.expectedCash ?? 0).toStringAsFixed(2)} DA · '
              'Compté : ${(shift.closingCash ?? 0).toStringAsFixed(2)} DA',
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            if (difference != null) ...[
              const SizedBox(height: 5),
              Text(
                'Écart : ${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(2)} DA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: difference.abs() < 0.01
                      ? AppColors.green
                      : AppColors.amber,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CashValueRow extends StatelessWidget {
  const _CashValueRow({
    required this.label,
    required this.value,
    this.prominent = false,
  });

  final String label;
  final double value;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: prominent ? 12 : 11,
            color: prominent ? null : AppColors.muted,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      Text(
        '${value.toStringAsFixed(2)} DA',
        style: TextStyle(
          fontSize: prominent ? 16 : 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _ShiftBadge extends StatelessWidget {
  const _ShiftBadge({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: (open ? AppColors.green : AppColors.muted).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      open ? 'Ouverte' : 'Clôturée',
      style: TextStyle(
        fontSize: 10,
        color: open ? AppColors.green : AppColors.muted,
      ),
    ),
  );
}

class _CashNotice extends StatelessWidget {
  const _CashNotice({required this.message, this.isError = false});

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

String _formatDate(DateTime? value) {
  if (value == null) return 'date inconnue';
  return DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR').format(value);
}
