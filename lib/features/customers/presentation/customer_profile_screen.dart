import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/data/current_role_cache.dart';
import '../../auth/data/supabase_auth_service.dart';
import '../data/customer_repository.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  late final CustomerRepository _repository;
  CustomerHomeSnapshot? _snapshot;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = CustomerRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _repository.loadHome();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121226),
        title: const Text('Se déconnecter ?'),
        content: const Text('Voulez-vous vraiment vous déconnecter de votre compte client ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );

    if (confirmed != true || _working) return;
    setState(() => _working = true);
    try {
      await SupabaseAuthService.instance.signOut();
      CurrentRoleCache.setRole(null);
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Déconnexion impossible : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final customer = _snapshot == null || _snapshot!.customers.isEmpty
        ? null
        : _snapshot!.customers.first;
    final fullName = customer?['full_name'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        'Joueur VIP';
    final email = user?.email ?? '';
    final phone = customer?['phone'] as String? ?? user?.phone ?? '';

    double wallet = 0;
    if (_snapshot != null && _snapshot!.balances.isNotEmpty) {
      wallet = (_snapshot!.balances.first['wallet_balance'] as num?)?.toDouble() ?? 0;
    }
    int points = 0;
    if (_snapshot != null && _snapshot!.loyaltyBalances.isNotEmpty) {
      points = (_snapshot!.loyaltyBalances.first['points_balance'] as num?)?.toInt() ?? 0;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const AppBottomNav(currentIndex: 4, isStaff: false),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
              children: [
                AppPageHeader(onBack: () => context.go('/customer/home')),
                const SizedBox(height: 18),
                const AppScreenTitle(
                  title: 'Mon Profil',
                  subtitle: 'Informations de votre compte client VIP',
                ),
                const SizedBox(height: 20),
                // Profile Avatar & Main Information Card
                AppSurface(
                  isSelected: true,
                  borderRadius: 26,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7A2FD6), Color(0xFFFF2D9B)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.pink.withValues(alpha: 0.4),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: const CircleAvatar(
                              radius: 32,
                              backgroundColor: AppColors.surface1,
                              child: Icon(
                                Icons.person_rounded,
                                size: 36,
                                color: AppColors.primaryLight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (email.isNotEmpty)
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                if (phone.isNotEmpty)
                                  Text(
                                    phone,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Account Balance Summary
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.green.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'PORTEFEUILLE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: AppColors.green,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${wallet.toStringAsFixed(0)} DA',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.pink.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.pink.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'POINTS FIDÉLITÉ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: AppColors.pink,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$points pts',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'OPTIONS ET RACCOURCIS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                AppSurface(
                  borderRadius: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.notifications_none_rounded, color: AppColors.pink),
                        title: const Text('Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Mes تنبيهات وحالة المشتريات', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        onTap: () => context.push('/notifications'),
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      ListTile(
                        leading: const Icon(Icons.receipt_long_rounded, color: AppColors.blueLight),
                        title: const Text('Factures et historique', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Historique des paiements', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        onTap: () => context.push('/invoices'),
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      ListTile(
                        leading: const Icon(Icons.help_outline_rounded, color: AppColors.amber),
                        title: const Text('Support et Aide', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Contacter l’équipe du lounge', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Contactez directement l’équipe à la caisse du Lounge.')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Prominent Sign Out Button (تسجيل الخروج)
                AppButton(
                  label: _working ? 'Déconnexion…' : 'Se déconnecter',
                  isGhost: true,
                  textColor: AppColors.red,
                  icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.red),
                  onPressed: _working ? () {} : _signOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
