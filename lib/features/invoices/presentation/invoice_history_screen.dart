import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../data/invoice_repository.dart';

class InvoiceHistoryScreen extends StatefulWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  late final InvoiceRepository _repository;
  InvoiceHistorySnapshot? _snapshot;
  RealtimeChannel? _channel;
  Timer? _reloadTimer;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repository = InvoiceRepository(Supabase.instance.client);
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
        snapshot.venueId,
        snapshot.userId,
        isCustomer: snapshot.isCustomer,
        onChange: _scheduleReload,
        onError: () {
          if (mounted) {
            setState(
              () => _error = 'La synchronisation des factures est interrompue.',
            );
          }
        },
      );
    } on PostgrestException catch (error) {
      debugPrint('Chargement des factures impossible : $error');
      if (mounted) {
        setState(() {
          _error =
              'Les factures n’ont pas pu être chargées. Vérifiez les autorisations et la connexion.';
          _loading = false;
        });
      }
    } on AuthException catch (error) {
      debugPrint('Accès aux factures impossible : $error');
      if (mounted) {
        setState(() {
          _error = 'Connectez-vous pour consulter les factures.';
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement des factures impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Les factures n’ont pas pu être chargées.';
          _loading = false;
        });
      }
    }
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 250), _load);
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
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
            children: [
              AppPageHeader(onBack: () => context.pop()),
              const SizedBox(height: 18),
              const AppScreenTitle(
                title: 'Factures',
                subtitle: 'Historique des règlements · 100 dernières',
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AppSurface(
                  borderRadius: 16,
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
              const SizedBox(height: 14),
              if (_loading && snapshot == null)
                const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot == null)
                const AppSurface(
                  borderRadius: 18,
                  child: Text(
                    'Le journal des factures n’est pas disponible.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                )
              else if (snapshot.invoices.isEmpty)
                const AppSurface(
                  borderRadius: 18,
                  child: Column(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: AppColors.muted,
                        size: 32,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Aucune facture à afficher.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                )
              else
                ...snapshot.invoices.map(_buildInvoiceCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(InvoiceRecord invoice) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Facture n° ${invoice.number}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  invoice.isSessionInvoice
                      ? 'Règlement d’une session'
                      : 'Commande hors session',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat(
                    'dd MMMM yyyy · HH:mm',
                    'fr_FR',
                  ).format(invoice.createdAt),
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${invoice.total.toStringAsFixed(2)} DA',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppColors.green,
            ),
          ),
        ],
      ),
    ),
  );
}
