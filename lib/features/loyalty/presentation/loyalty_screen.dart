import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/loyalty_repository.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  late final LoyaltyRepository _repository;
  LoyaltySnapshot? _snapshot;
  final List<RealtimeChannel> _channels = [];
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = LoyaltyRepository(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    for (final channel in _channels) {
      channel.unsubscribe();
    }
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
      if (_channels.isEmpty) {
        _channels.add(
          _repository.subscribeVenue(
            snapshot.venue.id,
            onChange: _scheduleReload,
            onError: _showRealtimeError,
          ),
        );
        final userChannel = _repository.subscribeUser(
          _scheduleReload,
          _showRealtimeError,
        );
        if (userChannel != null) _channels.add(userChannel);
      }
    } on PostgrestException catch (error) {
      debugPrint('Chargement de la fidélité impossible : $error');
      if (mounted) {
        setState(() {
          _error = 'Les données de fidélité n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement de la fidélité impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les données de fidélité n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    }
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 250), _load);
  }

  void _showRealtimeError() {
    if (mounted) {
      setState(
        () => _error = 'La synchronisation de la fidélité est interrompue.',
      );
    }
  }

  Future<void> _editReward([LoyaltyReward? existing]) async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.venue.canManageCatalog || _working) {
      return;
    }
    final form = await showDialog<_RewardForm>(
      context: context,
      builder: (context) => _RewardFormDialog(existing: existing),
    );
    if (form == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.saveReward(
        venueId: snapshot.venue.id,
        name: form.name,
        description: form.description,
        pointsCost: form.pointsCost,
        stockQuantity: form.stockQuantity,
        rewardId: existing?.id,
      );
      await _load();
    } on LoyaltyException catch (error) {
      if (mounted) setState(() => _error = _message(error.code));
    } on PostgrestException catch (error) {
      debugPrint('Enregistrement de la récompense impossible : $error');
      if (mounted) setState(() => _error = _message(error.message));
    } catch (error, stackTrace) {
      debugPrint('Enregistrement de la récompense impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La récompense n’a pas été enregistrée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleReward(LoyaltyReward reward) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await _repository.setRewardActive(reward.id, !reward.isActive);
      await _load();
    } on PostgrestException catch (error) {
      debugPrint('Modification de la récompense impossible : $error');
      if (mounted) setState(() => _error = _message(error.message));
    } on LoyaltyException catch (error) {
      if (mounted) setState(() => _error = _message(error.code));
    } catch (error, stackTrace) {
      debugPrint('Modification de la récompense impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le statut de la récompense n’a pas changé.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _decide(LoyaltyRedemption redemption, bool approve) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.decideRedemption(
        redemptionId: redemption.id,
        approve: approve,
      );
      await _load();
    } on PostgrestException catch (error) {
      debugPrint('Traitement de la récompense impossible : $error');
      if (mounted) setState(() => _error = _message(error.message));
    } catch (error, stackTrace) {
      debugPrint('Traitement de la récompense impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La demande n’a pas pu être traitée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _message(String error) {
    final code = error.split(':').first.trim().toUpperCase();
    return switch (code) {
      'FORBIDDEN' || '42501' => 'Votre rôle ne permet pas cette opération.',
      'INVALID_REWARD' || '23514' => 'Vérifiez le nom, le coût et le stock.',
      'REWARD_NOT_FOUND' =>
        'Cette récompense a été supprimée ou vous ne pouvez plus la modifier.',
      'REDEMPTION_ALREADY_HANDLED' =>
        'Cette demande a déjà été traitée par un membre de l’équipe.',
      _ => 'Une erreur est survenue. Réessayez.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final canManage = snapshot?.venue.canManageCatalog ?? false;
    final pending =
        snapshot?.redemptions
            .where((item) => item.status == 'pending')
            .toList() ??
        const <LoyaltyRedemption>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
            children: [
              AppScreenTitle(
                title: 'Fidélité',
                subtitle: 'Points non monétaires et récompenses',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canManage)
                      IconButton.filled(
                        tooltip: 'Ajouter une récompense',
                        onPressed: _working ? null : () => _editReward(),
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
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot == null)
                const AppSurface(
                  borderRadius: 18,
                  child: Text(
                    'Les données de fidélité ne sont pas disponibles.',
                  ),
                )
              else ...[
                const SizedBox(height: 14),
                const Text(
                  'Demandes à traiter',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: AppSurface(
                      borderRadius: 16,
                      child: Text('Aucune demande de récompense en attente.'),
                    ),
                  )
                else
                  ...pending.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: AppSurface(
                        borderRadius: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.customerName} · ${item.rewardName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${item.pointsCost} points',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: _working
                                      ? null
                                      : () => _decide(item, false),
                                  child: const Text('Refuser'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _working
                                      ? null
                                      : () => _decide(item, true),
                                  child: const Text('Remise effectuée'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                const Text(
                  'Catalogue des récompenses',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (snapshot.rewards.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: AppSurface(
                      borderRadius: 16,
                      child: Text('Aucune récompense configurée.'),
                    ),
                  )
                else
                  ...snapshot.rewards.map(
                    (reward) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: AppSurface(
                        borderRadius: 18,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.card_giftcard_rounded,
                              color: AppColors.pink,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reward.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${reward.pointsCost} points · '
                                    '${reward.stockQuantity == null ? 'Stock illimité' : 'Stock ${reward.stockQuantity}'}'
                                    '${reward.isActive ? '' : ' · Désactivée'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  if (reward.description?.isNotEmpty == true)
                                    Text(
                                      reward.description!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (canManage) ...[
                              IconButton(
                                tooltip: 'Modifier',
                                onPressed: _working
                                    ? null
                                    : () => _editReward(reward),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              Switch(
                                value: reward.isActive,
                                onChanged: _working
                                    ? null
                                    : (_) => _toggleReward(reward),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardForm {
  const _RewardForm({
    required this.name,
    required this.description,
    required this.pointsCost,
    required this.stockQuantity,
  });

  final String name;
  final String description;
  final int pointsCost;
  final int? stockQuantity;
}

class _RewardFormDialog extends StatefulWidget {
  const _RewardFormDialog({this.existing});

  final LoyaltyReward? existing;

  @override
  State<_RewardFormDialog> createState() => _RewardFormDialogState();
}

class _RewardFormDialogState extends State<_RewardFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _description = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _points = TextEditingController(
    text: widget.existing?.pointsCost.toString() ?? '',
  );
  late final _stock = TextEditingController(
    text: widget.existing?.stockQuantity?.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _points.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null
          ? 'Nouvelle récompense'
          : 'Modifier la récompense',
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
            controller: _points,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Coût en points'),
          ),
          TextField(
            controller: _stock,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantité en stock (vide = illimitée)',
            ),
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
          final points = int.tryParse(_points.text.trim());
          final stock = _stock.text.trim().isEmpty
              ? null
              : int.tryParse(_stock.text.trim());
          if (_name.text.trim().isEmpty ||
              points == null ||
              points < 1 ||
              (_stock.text.trim().isNotEmpty && (stock == null || stock < 0))) {
            setState(() => _error = 'Vérifiez le nom, les points et le stock.');
            return;
          }
          Navigator.pop(
            context,
            _RewardForm(
              name: _name.text,
              description: _description.text,
              pointsCost: points,
              stockQuantity: stock,
            ),
          );
        },
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
