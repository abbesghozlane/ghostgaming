import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/audit_log_repository.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  late final AuditLogRepository _repository;
  List<AuditLogEntry>? _entries;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repository = AuditLogRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _repository.load();
      if (!mounted) return;
      setState(() => _entries = entries);
    } on AuditLogException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on PostgrestException catch (error) {
      debugPrint('Chargement du journal d’activité impossible : $error');
      if (mounted) {
        setState(
          () => _error =
              'Le journal n’a pas pu être chargé. Vérifiez les autorisations et la connexion.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement du journal d’activité impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le journal n’a pas pu être chargé.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
                children: [
                  AppPageHeader(onBack: () => context.pop()),
                  const SizedBox(height: 18),
                  const AppScreenTitle(
                    title: 'Journal d’activité',
                    subtitle: 'Les 100 opérations les plus récentes',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AppSurface(
                      borderRadius: 18,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.red,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Réessayer',
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_loading && _entries == null)
                    const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_entries?.isEmpty == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 28),
                      child: AppSurface(
                        borderRadius: 18,
                        child: Text(
                          'Aucune activité enregistrée pour le moment.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                    )
                  else
                    ...?_entries?.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _AuditEntryCard(entry: entry),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const AppBottomNav(currentIndex: 4, isStaff: true),
        ],
      ),
    ),
  );
}

class _AuditEntryCard extends StatelessWidget {
  const _AuditEntryCard({required this.entry});

  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final date = entry.createdAt;
    final dateLabel = date == null
        ? 'Date inconnue'
        : DateFormat('dd MMMM yyyy · HH:mm', 'fr_FR').format(date);
    final reference = entry.metadata.entries
        .where((item) => item.value is String || item.value is num)
        .map((item) => '${_metadataLabel(item.key)} : ${item.value}')
        .take(2)
        .join(' · ');
    return AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.primaryLight,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auditActionLabel(entry.action),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_entityLabel(entry.entityType)}'
                  '${entry.entityId == null ? '' : ' · ${_shortId(entry.entityId!)}'}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                if (reference.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    reference,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${entry.actorId == null ? 'Système' : 'Compte ${_shortId(entry.actorId!)}'} · $dateLabel',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _shortId(String value) => value.length <= 8
    ? value
    : '${value.substring(0, 4)}…${value.substring(value.length - 4)}';

String _entityLabel(String value) => switch (value) {
  'session' => 'Session',
  'order' => 'Commande',
  'product' => 'Produit',
  'venue_member' => 'Employé',
  'staff_invitation' => 'Invitation',
  'session_request' => 'Demande',
  _ => value,
};

String _metadataLabel(String value) => switch (value) {
  'amount' || 'total' => 'Montant',
  'quantity' || 'qty' => 'Quantité',
  'minutes' => 'Minutes',
  'game' => 'Jeu',
  'post' => 'Poste',
  'reason' => 'Motif',
  'email' => 'E-mail',
  'from' => 'Depuis',
  'to' => 'Vers',
  _ => value,
};
