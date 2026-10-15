import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/utils/venue_time_zone.dart';
import '../data/promotion_repository.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  late final PromotionRepository _repository;
  PromotionSnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = PromotionRepository(Supabase.instance.client);
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
      _channel ??= _repository.subscribe(
          snapshot.venue.id,
          onChange: _scheduleReload,
          onError: () {
            if (mounted) {
              setState(
                () => _error =
                    'La synchronisation des promotions est interrompue.',
              );
            }
          },
        );
    } on PostgrestException catch (error) {
      debugPrint('Chargement des promotions impossible : $error');
      if (mounted) {
        setState(() {
          _error = 'Les promotions n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des promotions impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les promotions n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    }
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _editPromotion([Promotion? existing]) async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.venue.canManageCatalog || _working) {
      return;
    }
    final form = await showDialog<_PromotionForm>(
      context: context,
      builder: (context) => _PromotionFormDialog(
        existing: existing,
        timeZone: snapshot.venue.timeZone,
      ),
    );
    if (form == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.save(
        venueId: snapshot.venue.id,
        name: form.name,
        description: form.description,
        discountPercent: form.discountPercent,
        startsAt: form.startsAt,
        endsAt: form.endsAt,
        timeZone: snapshot.venue.timeZone,
        promotionId: existing?.id,
      );
      await _load();
    } on PromotionException catch (error) {
      if (mounted) setState(() => _error = _message(error.code));
    } on PostgrestException catch (error) {
      debugPrint('Enregistrement de la promotion impossible : $error');
      if (mounted) setState(() => _error = _message(error.message));
    } catch (error, stackTrace) {
      debugPrint('Enregistrement de la promotion impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La promotion n’a pas pu être enregistrée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggle(Promotion promotion) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.setActive(promotion.id, !promotion.isActive);
      await _load();
    } on PostgrestException catch (error) {
      debugPrint('Modification de la promotion impossible : $error');
      if (mounted) setState(() => _error = _message(error.message));
    } catch (error, stackTrace) {
      debugPrint('Modification de la promotion impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le statut de la promotion n’a pas changé.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _message(String error) {
    final code = error.split(':').first.trim().toUpperCase();
    if (code == 'FORBIDDEN' || code == '42501') {
      return 'Votre rôle ne permet pas de gérer les promotions.';
    }
    if (code == 'INVALID_PROMOTION' || code == '23514') {
      return 'Vérifiez le nom, le pourcentage et les dates.';
    }
    return 'Une erreur est survenue. Réessayez.';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final canManage = snapshot?.venue.canManageCatalog ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
            children: [
              AppScreenTitle(
                title: 'Promotions',
                subtitle: 'Réductions de session limitées dans le temps',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canManage)
                      IconButton.filled(
                        tooltip: 'Créer une promotion',
                        onPressed: _working ? null : () => _editPromotion(),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    IconButton(
                      tooltip: 'Retour',
                      onPressed: () => context.go('/home'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot?.promotions.isEmpty ?? true)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: AppSurface(
                    borderRadius: 20,
                    child: Text(
                      'Aucune promotion configurée.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...snapshot!.promotions.map(
                  (promotion) => _PromotionCard(
                    promotion: promotion,
                    canManage: canManage,
                    busy: _working,
                    onEdit: () => _editPromotion(promotion),
                    onToggle: () => _toggle(promotion),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.promotion,
    required this.canManage,
    required this.busy,
    required this.onEdit,
    required this.onToggle,
  });

  final Promotion promotion;
  final bool canManage;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = !promotion.isActive
        ? 'Désactivée'
        : promotion.activeAt(now)
        ? 'En cours'
        : promotion.startsAt.isAfter(now)
        ? 'Programmée'
        : 'Expirée';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppSurface(
        borderRadius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    promotion.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '-${promotion.discountPercent.toStringAsFixed(0)} %',
                  style: const TextStyle(
                    color: AppColors.pink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (promotion.description?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                promotion.description!,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 7),
            Text(
              '$status · ${_date(promotion.startsAt)} → ${_date(promotion.endsAt)}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            if (canManage) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  const Spacer(),
                  Switch(
                    value: promotion.isActive,
                    onChanged: busy ? null : (_) => onToggle(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _date(DateTime value) =>
      DateFormat('dd MMMM yyyy', 'fr_FR').format(value);
}

class _PromotionForm {
  const _PromotionForm({
    required this.name,
    required this.description,
    required this.discountPercent,
    required this.startsAt,
    required this.endsAt,
  });

  final String name;
  final String description;
  final double discountPercent;
  final DateTime startsAt;
  final DateTime endsAt;
}

class _PromotionFormDialog extends StatefulWidget {
  const _PromotionFormDialog({
    required this.timeZone,
    this.existing,
  });

  final String timeZone;
  final Promotion? existing;

  @override
  State<_PromotionFormDialog> createState() => _PromotionFormDialogState();
}

class _PromotionFormDialogState extends State<_PromotionFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _percent = TextEditingController(
    text: widget.existing?.discountPercent.toStringAsFixed(0) ?? '10',
  );
  late DateTime _startsAt =
      widget.existing?.startsAt ?? _venueDate(widget.timeZone);
  late DateTime _endsAt =
      widget.existing?.endsAt ?? _venueDate(widget.timeZone, days: 8);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final now = VenueTimeZone.now(widget.timeZone);
    final current = start ? _startsAt : _venueDateFor(
      widget.timeZone,
      _endsAt.year,
      _endsAt.month,
      _endsAt.day - 1,
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: _venueDateFor(
        widget.timeZone,
        now.year,
        now.month,
        now.day - 365,
      ),
      lastDate: _venueDateFor(
        widget.timeZone,
        now.year,
        now.month,
        now.day + 730,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startsAt = _venueDateFor(
          widget.timeZone,
          picked.year,
          picked.month,
          picked.day,
        );
      } else {
        _endsAt = _venueDateFor(
          widget.timeZone,
          picked.year,
          picked.month,
          picked.day + 1,
        );
      }
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Nouvelle promotion' : 'Modifier la promotion',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          TextField(
            controller: _description,
            maxLength: 240,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextField(
            controller: _percent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Réduction en pourcentage',
              suffixText: '%',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Début : ${_date(_startsAt)}'),
              ),
              TextButton(
                onPressed: () => _pickDate(start: true),
                child: const Text('Choisir'),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Fin : ${_date(_venueDateFor(widget.timeZone, _endsAt.year, _endsAt.month, _endsAt.day - 1))}',
                ),
              ),
              TextButton(
                onPressed: () => _pickDate(start: false),
                child: const Text('Choisir'),
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () {
          final percent = double.tryParse(
            _percent.text.trim().replaceAll(',', '.'),
          );
          if (_name.text.trim().isEmpty ||
              percent == null ||
              !percent.isFinite ||
              percent <= 0 ||
              percent > 100 ||
              !_endsAt.isAfter(_startsAt)) {
            setState(() => _error = 'Vérifiez les champs et les dates.');
            return;
          }

          Navigator.pop(
            context,
            _PromotionForm(
              name: _name.text,
              description: _description.text,
              discountPercent: percent,
              startsAt: _startsAt,
              endsAt: _endsAt,
            ),
          );
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );

  String _date(DateTime value) =>
      DateFormat('dd MMMM yyyy', 'fr_FR').format(value);
}

DateTime _venueDate(String timeZone, {int days = 0}) {
  final now = VenueTimeZone.now(timeZone);
  return _venueDateFor(timeZone, now.year, now.month, now.day + days);
}

DateTime _venueDateFor(String timeZone, int year, int month, int day) =>
    VenueTimeZone.dateTime(
      timeZone,
      year: year,
      month: month,
      day: day,
    );
