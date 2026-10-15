import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/utils/venue_time_zone.dart';
import '../data/program_repository.dart';

class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  late final ProgramRepository _repository;
  ProgramSnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = ProgramRepository(Supabase.instance.client);
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
              () => _error = 'La synchronisation des offres est interrompue.',
            );
          }
        },
      );
    } on PostgrestException catch (error) {
      debugPrint('Chargement des programmes impossible : $error');
      if (mounted) {
        setState(() {
          _error = 'Les programmes clients n’ont pas pu être chargés.';
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des programmes impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les programmes clients n’ont pas pu être chargés.';
          _loading = false;
        });
      }
    }
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _savePlan([Map<String, dynamic>? existing]) async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.venue.canManageCatalog || _working) {
      return;
    }
    final form = await showDialog<_MembershipPlanForm>(
      context: context,
      builder: (context) => _MembershipPlanDialog(existing: existing),
    );
    if (form == null) {
      return;
    }
    await _run(
      () => _repository.saveMembershipPlan(
        planId: existing?['id'] as String?,
        venueId: snapshot.venue.id,
        name: form.name,
        durationDays: form.durationDays,
        benefits: form.benefits,
      ),
    );
  }

  Future<void> _savePackage([Map<String, dynamic>? existing]) async {
    final snapshot = _snapshot;
    if (snapshot == null || !snapshot.venue.canManageCatalog || _working) {
      return;
    }
    final form = await showDialog<_PackageForm>(
      context: context,
      builder: (context) =>
          _PackageDialog(existing: existing, products: snapshot.products),
    );
    if (form == null) {
      return;
    }
    await _run(
      () => _repository.savePackage(
        packageId: existing?['id'] as String?,
        name: form.name,
        description: form.description,
        price: form.price,
        gamingMinutes: form.gamingMinutes,
        items: form.items,
      ),
    );
  }

  Future<void> _activateMembership() async {
    final snapshot = _snapshot;
    if (snapshot == null || _working) return;
    final action = await showDialog<_ProgramAction>(
      context: context,
      builder: (context) => _ProgramActionDialog(
        title: 'Activer une adhésion',
        customers: snapshot.customers,
        options: snapshot.membershipPlans.where(_isActive).toList(),
        optionLabel: (row) => '${row['name']} · ${row['duration_days']} jours',
      ),
    );
    if (action == null) return;
    await _run(
      () => _repository.assignMembership(
        customerId: action.customerId,
        planId: action.optionId,
      ),
      successMessage: 'Adhésion activée pour le client.',
    );
  }

  Future<void> _sellPackage() async {
    final snapshot = _snapshot;
    if (snapshot == null || _working) return;
    final action = await showDialog<_ProgramAction>(
      context: context,
      builder: (context) => _ProgramActionDialog(
        title: 'Vendre une formule',
        customers: snapshot.customers,
        options: snapshot.packages.where(_isActive).toList(),
        optionLabel: (row) => '${row['name']} · ${_money(row['price'])} DA',
        requireMethod: true,
      ),
    );
    if (action == null) return;
    await _run(
      () => _repository.sellPackage(
        customerId: action.customerId,
        packageId: action.optionId,
        method: action.method,
      ),
      successMessage: 'Formule vendue. Paiement et facture enregistrés.',
    );
  }

  Future<void> _redeemItem(Map<String, dynamic> item) async {
    if (_working) return;
    await _run(
      () => _repository.redeemProduct(
        purchaseItemId: item['id'] as String,
        quantity: 1,
      ),
      successMessage: 'Produit remis au client.',
    );
  }

  Future<void> _setActive({
    required String id,
    required bool active,
    required bool membership,
  }) async {
    if (_working) return;
    await _run(
      () => membership
          ? _repository.setMembershipPlanActive(id, active)
          : _repository.setPackageActive(id, active),
    );
  }

  Future<void> _run(
    Future<void> Function() operation, {
    String? successMessage,
  }) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await operation();
      await _load();
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on ProgramException catch (error) {
      if (mounted) setState(() => _error = _message(error.code));
    } on PostgrestException catch (error) {
      debugPrint('Opération sur les programmes impossible : $error');
      if (mounted) setState(() => _error = _message(error.message));
    } catch (error, stackTrace) {
      debugPrint('Opération sur les programmes impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _error = 'L’opération a échoué.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _message(String raw) {
    final value = raw.toUpperCase();
    if (value.contains('MEMBERSHIP_ALREADY_ACTIVE')) {
      return 'Ce client possède déjà une adhésion active.';
    }
    if (value.contains('INSUFFICIENT_STOCK')) {
      return 'Stock insuffisant pour vendre cette formule.';
    }
    if (value.contains('PACKAGE_PRODUCT_NOT_AVAILABLE')) {
      return 'Un produit de cette formule n’est plus disponible.';
    }
    if (value.contains('PACKAGE_EXPIRED')) {
      return 'Ce forfait a expiré.';
    }
    if (value.contains('FORBIDDEN') || value.contains('42501')) {
      return 'Votre rôle ne permet pas cette opération.';
    }
    if (value.contains('INVALID_') || value.contains('23514')) {
      return 'Vérifiez les valeurs saisies.';
    }
    if (value.contains('NOT_FOUND')) {
      return 'Cet élément n’existe plus ou n’est plus accessible.';
    }
    return 'L’opération a échoué. Actualisez puis réessayez.';
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
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
            children: [
              AppScreenTitle(
                title: 'Adhésions & formules',
                subtitle: 'Avantages informatifs et forfaits prépayés',
                trailing: IconButton(
                  tooltip: 'Retour',
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.arrow_back_rounded),
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
              else if (snapshot == null)
                const AppSurface(
                  borderRadius: 18,
                  child: Text('Les offres ne sont pas disponibles.'),
                )
              else ...[
                const SizedBox(height: 12),
                _sectionHeading(
                  'Adhésions',
                  canManage ? () => _savePlan() : null,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 8),
                  child: Text(
                    'Les avantages sont descriptifs : aucun rabais automatique n’est appliqué.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
                if (snapshot.membershipPlans.isEmpty)
                  _empty('Aucune adhésion configurée.')
                else
                  ...snapshot.membershipPlans.map(
                    (plan) => _planCard(plan, canManage),
                  ),
                if (canManage) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _activateMembership,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Activer pour un client'),
                  ),
                ],
                const SizedBox(height: 22),
                _sectionHeading(
                  'Formules prépayées',
                  canManage ? () => _savePackage() : null,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 8),
                  child: Text(
                    'Chaque formule comprend des minutes et peut inclure des produits du stock.',
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ),
                if (snapshot.packages.isEmpty)
                  _empty('Aucune formule configurée.')
                else
                  ...snapshot.packages.map(
                    (package) => _packageCard(package, canManage),
                  ),
                if (snapshot.packages.any(_isActive)) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _working ? null : _sellPackage,
                    icon: const Icon(Icons.point_of_sale_rounded),
                    label: const Text('Vendre une formule'),
                  ),
                ],
                const SizedBox(height: 22),
                _heading('Adhésions clients'),
                if (snapshot.memberships.isEmpty)
                  _empty('Aucune adhésion attribuée.')
                else
                  ...snapshot.memberships.map(
                    (row) => _membershipRecord(row, snapshot.venue.timeZone),
                  ),
                const SizedBox(height: 22),
                _heading('Forfaits clients'),
                if (snapshot.purchases.isEmpty)
                  _empty('Aucun forfait vendu.')
                else
                  ...snapshot.purchases.map(
                    (row) => _purchaseCard(row, snapshot.venue.timeZone),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String title, VoidCallback? add) => Row(
    children: [
      Expanded(child: _heading(title)),
      if (add != null)
        IconButton(
          tooltip: 'Ajouter',
          onPressed: _working ? null : add,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
    ],
  );

  Widget _heading(String title) => Text(
    title,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: AppSurface(
      borderRadius: 16,
      child: Text(text, style: const TextStyle(color: AppColors.muted)),
    ),
  );

  Widget _planCard(Map<String, dynamic> plan, bool canManage) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppSurface(
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan['name'] as String? ?? 'Adhésion',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${plan['duration_days']} jours${_isActive(plan) ? '' : ' · Désactivée'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _savePlan(plan);
                      if (value == 'toggle') {
                        _setActive(
                          id: plan['id'] as String,
                          active: !_isActive(plan),
                          membership: true,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Modifier'),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(_isActive(plan) ? 'Désactiver' : 'Activer'),
                      ),
                    ],
                  ),
              ],
            ),
            if ((plan['benefits'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  plan['benefits'] as String,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _packageCard(Map<String, dynamic> package, bool canManage) {
    final items = (package['package_items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final itemLabel = items
        .map((item) {
          final product = _map(item['products']);
          return '${item['quantity']} × ${product?['name'] ?? 'Produit'}';
        })
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppSurface(
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    package['name'] as String? ?? 'Formule',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${_money(package['price'])} DA${_isActive(package) ? '' : ' · Désactivée'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _savePackage(package);
                      if (value == 'toggle') {
                        _setActive(
                          id: package['id'] as String,
                          active: !_isActive(package),
                          membership: false,
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Modifier'),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          _isActive(package) ? 'Désactiver' : 'Activer',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Text(
              '${package['gaming_minutes']} min de jeu${itemLabel.isEmpty ? '' : ' · $itemLabel'}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            if ((package['description'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  package['description'] as String,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _membershipRecord(Map<String, dynamic> row, String timeZone) {
    final customer = _map(row['customers']);
    final end = VenueTimeZone.parse(row['ends_at'] as String?, timeZone);
    final active = end != null && end.isAfter(VenueTimeZone.now(timeZone));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppSurface(
        borderRadius: 16,
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${customer?['full_name'] ?? 'Client'} · ${row['plan_name']}',
                  ),
                  Text(
                    active
                        ? 'Active jusqu’au ${_date(end)}'
                        : 'Expirée le ${_date(end)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _purchaseCard(Map<String, dynamic> row, String timeZone) {
    final customer = _map(row['customers']);
    final items = (row['package_purchase_items'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final expiry = VenueTimeZone.parse(row['expires_at'] as String?, timeZone);
    final expired =
        expiry == null || !expiry.isAfter(VenueTimeZone.now(timeZone));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppSurface(
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${customer?['full_name'] ?? 'Client'} · ${row['package_name']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${expired ? 'Forfait expiré' : '${row['gaming_minutes_remaining']} minutes restantes'}'
              '${expiry == null ? '' : ' · expire le ${_date(expiry)}'}',
              style: TextStyle(
                fontSize: 11,
                color: expired ? AppColors.red : AppColors.muted,
              ),
            ),
            for (final item in items)
              if (!expired && (item['remaining_quantity'] as num).toInt() > 0)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item['product_name']} · reste ${item['remaining_quantity']}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    TextButton(
                      onPressed: _working ? null : () => _redeemItem(item),
                      child: const Text('Remettre 1'),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  bool _isActive(Map<String, dynamic> row) =>
      row['is_active'] as bool? ?? false;

  Map<String, dynamic>? _map(dynamic value) =>
      value is Map<String, dynamic> ? value : null;

  String _money(dynamic value) =>
      ((value as num?)?.toDouble() ?? 0).toStringAsFixed(2);

  String _date(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('dd MMMM yyyy', 'fr_FR').format(value);
  }
}

class _MembershipPlanForm {
  const _MembershipPlanForm(this.name, this.durationDays, this.benefits);

  final String name;
  final int durationDays;
  final String benefits;
}

class _MembershipPlanDialog extends StatefulWidget {
  const _MembershipPlanDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_MembershipPlanDialog> createState() => _MembershipPlanDialogState();
}

class _MembershipPlanDialogState extends State<_MembershipPlanDialog> {
  late final TextEditingController _name;
  late final TextEditingController _days;
  late final TextEditingController _benefits;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?['name'] as String?);
    _days = TextEditingController(
      text: '${widget.existing?['duration_days'] ?? 30}',
    );
    _benefits = TextEditingController(
      text: widget.existing?['benefits'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    _benefits.dispose();
    super.dispose();
  }

  void _save() {
    final days = int.tryParse(_days.text);
    if (_name.text.trim().isEmpty || days == null || days < 1 || days > 3650) {
      setState(
        () => _error = 'Saisissez un nom et une durée valide (1–3650 jours).',
      );
      return;
    }
    Navigator.pop(
      context,
      _MembershipPlanForm(_name.text.trim(), days, _benefits.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Nouvelle adhésion' : 'Modifier l’adhésion',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nom'),
          ),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Durée (jours)'),
          ),
          TextField(
            controller: _benefits,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Avantages informatifs',
              helperText:
                  'Aucun avantage ne modifie automatiquement la facture.',
            ),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );
}

class _PackageForm {
  const _PackageForm({
    required this.name,
    required this.description,
    required this.price,
    required this.gamingMinutes,
    required this.items,
  });

  final String name;
  final String description;
  final double price;
  final int gamingMinutes;
  final List<Map<String, dynamic>> items;
}

class _PackageDialog extends StatefulWidget {
  const _PackageDialog({required this.products, this.existing});

  final List<Map<String, dynamic>> products;
  final Map<String, dynamic>? existing;

  @override
  State<_PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends State<_PackageDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _minutes;
  final Map<String, int> _quantities = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _name = TextEditingController(text: row?['name'] as String?);
    _description = TextEditingController(text: row?['description'] as String?);
    _price = TextEditingController(text: row?['price']?.toString() ?? '');
    _minutes = TextEditingController(
      text: row?['gaming_minutes']?.toString() ?? '60',
    );
    for (final item
        in (row?['package_items'] as List? ?? const [])
            .cast<Map<String, dynamic>>()) {
      _quantities[item['product_id'] as String] = (item['quantity'] as num)
          .toInt();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final price = double.tryParse(_price.text.replaceAll(',', '.'));
    final minutes = int.tryParse(_minutes.text);
    if (_name.text.trim().isEmpty ||
        price == null ||
        !price.isFinite ||
        price <= 0 ||
        minutes == null ||
        minutes < 1 ||
        minutes > 100000) {
      setState(() => _error = 'Vérifiez le nom, le prix et les minutes.');
      return;
    }
    if (_quantities.values.every((quantity) => quantity == 0)) {
      setState(() => _error = 'Ajoutez au moins un produit à la formule.');
      return;
    }
    Navigator.pop(
      context,
      _PackageForm(
        name: _name.text.trim(),
        description: _description.text.trim(),
        price: price,
        gamingMinutes: minutes,
        items: [
          for (final entry in _quantities.entries)
            if (entry.value > 0)
              {'product_id': entry.key, 'quantity': entry.value},
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Nouvelle formule' : 'Modifier la formule',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description (facultative)',
              ),
            ),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Prix total (DA)'),
            ),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minutes de jeu'),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Produits inclus',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final product in widget.products)
              _ProductQuantityRow(
                product: product,
                quantity: _quantities[product['id'] as String] ?? 0,
                onChanged: (value) => setState(
                  () => _quantities[product['id'] as String] = value,
                ),
              ),
            if (widget.products.isEmpty)
              const Text('Aucun produit disponible.'),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Enregistrer')),
    ],
  );
}

class _ProductQuantityRow extends StatelessWidget {
  const _ProductQuantityRow({
    required this.product,
    required this.quantity,
    required this.onChanged,
  });

  final Map<String, dynamic> product;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(product['name'] as String? ?? 'Produit')),
      IconButton(
        onPressed: quantity > 0 ? () => onChanged(quantity - 1) : null,
        icon: const Icon(Icons.remove_circle_outline),
      ),
      Text('$quantity'),
      IconButton(
        onPressed: quantity < 100 ? () => onChanged(quantity + 1) : null,
        icon: const Icon(Icons.add_circle_outline),
      ),
    ],
  );
}

class _ProgramAction {
  const _ProgramAction(this.customerId, this.optionId, this.method);

  final String customerId;
  final String optionId;
  final String method;
}

class _ProgramActionDialog extends StatefulWidget {
  const _ProgramActionDialog({
    required this.title,
    required this.customers,
    required this.options,
    required this.optionLabel,
    this.requireMethod = false,
  });

  final String title;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> options;
  final String Function(Map<String, dynamic>) optionLabel;
  final bool requireMethod;

  @override
  State<_ProgramActionDialog> createState() => _ProgramActionDialogState();
}

class _ProgramActionDialogState extends State<_ProgramActionDialog> {
  String? _customerId;
  String? _optionId;
  String _method = 'cash';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _customerId,
          decoration: const InputDecoration(labelText: 'Client'),
          items: widget.customers
              .map(
                (row) => DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(row['full_name'] as String? ?? 'Client'),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _customerId = value),
        ),
        DropdownButtonFormField<String>(
          initialValue: _optionId,
          decoration: const InputDecoration(labelText: 'Offre'),
          items: widget.options
              .map(
                (row) => DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(widget.optionLabel(row)),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _optionId = value),
        ),
        if (widget.requireMethod)
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Paiement'),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Espèces')),
              DropdownMenuItem(value: 'card', child: Text('Carte')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _method = value);
            },
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _customerId == null || _optionId == null
            ? null
            : () => Navigator.pop(
                context,
                _ProgramAction(_customerId!, _optionId!, _method),
              ),
        child: const Text('Confirmer'),
      ),
    ],
  );
}
