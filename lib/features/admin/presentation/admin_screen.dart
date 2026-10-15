import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../auth/data/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'archive_reset_dialog.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final venueName =
        user?.userMetadata?['venue_name']?.toString() ?? 'Votre salle';
    final email = user?.email ?? 'Compte authentifié';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 92),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AppSurface(
                        borderRadius: 15,
                        padding: const EdgeInsets.all(10),
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/home');
                          }
                        },
                        child: const Icon(Icons.arrow_back_rounded, size: 22),
                      ),
                      Column(
                        children: [
                          Text(
                            'GHOST',
                            style: TextStyle(
                              fontFamily: 'Orbitron',
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              letterSpacing: 1.5,
                              color: const Color(0xFFC6E8FF),
                            ),
                          ),
                          Text(
                            'GAMING',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              fontSize: 9,
                              letterSpacing: 3.42,
                              color: const Color(0xFF8197CF),
                            ),
                          ),
                        ],
                      ),
                      AppSurface(
                        borderRadius: 15,
                        padding: const EdgeInsets.all(10),
                        onTap: () => context.push('/notifications'),
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Administration',
                    style: Theme.of(
                      context,
                    ).textTheme.displayLarge?.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Gestion de votre salle',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  // Profile Card
                  AppSurface(
                    isSelected: true,
                    borderRadius: 26,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7A2FD6), AppColors.pink],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x99BE32DC),
                                offset: const Offset(0, 10),
                                blurRadius: 22,
                                spreadRadius: -4,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'G',
                            style: TextStyle(
                              fontFamily: 'Orbitron',
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venueName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: AppColors.pink.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: AppColors.pink.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'COMPTE ACTIF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                    color: Color(0xFFFFD1EC),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppSurface(
                          borderRadius: 13,
                          padding: const EdgeInsets.all(10),
                          onTap: () => context.go('/settings'),
                          child: const Icon(Icons.edit_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'GESTION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppSurface(
                    borderRadius: 24,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          context,
                          icon: Icons.sports_esports_rounded,
                          gradientColors: [
                            Color(0xFF3B82F6),
                            Color(0xFF6366F1),
                          ],
                          title: 'Postes',
                          subtitle: 'Ajouter, désactiver, QR code',
                          onTap: () => context.go('/posts'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.disc_full_rounded,
                          gradientColors: [
                            AppColors.primary,
                            Color(0xFFC026D3),
                          ],
                          title: 'Jeux & Tarifs',
                          subtitle: 'Prix par match ou par temps',
                          onTap: () => context.go('/games'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.inventory_2_rounded,
                          gradientColors: [AppColors.amber, AppColors.red],
                          title: 'Produits & Inventaire',
                          subtitle: 'Stock, seuil minimum',
                          onTap: () => context.go('/inventory'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.group_rounded,
                          gradientColors: [AppColors.green, Color(0xFF06B6D4)],
                          title: 'Employés & Permissions',
                          subtitle: 'Rôles, remises, annulations',
                          onTap: () => context.go('/employees'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.account_balance_wallet_rounded,
                          gradientColors: [
                            Color(0xFFEC4899),
                            Color(0xFFF43F5E),
                          ],
                          title: 'Clients, Wallet & Crédit',
                          subtitle: 'Soldes et dettes',
                          onTap: () => context.go('/customers'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.card_giftcard_rounded,
                          gradientColors: [AppColors.pink, AppColors.amber],
                          title: 'Fidélité',
                          subtitle: 'Points et récompenses clients',
                          onTap: () => context.go('/loyalty'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.card_membership_rounded,
                          gradientColors: [AppColors.blueLight, AppColors.green],
                          title: 'Adhésions & formules',
                          subtitle: 'Avantages clients et forfaits prépayés',
                          onTap: () => context.go('/programs'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'FINANCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppSurface(
                    borderRadius: 24,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          context,
                          icon: Icons.access_time_rounded,
                          gradientColors: [
                            Color(0xFF0EA5E9),
                            Color(0xFF3B82F6),
                          ],
                          title: 'Services & Caisse',
                          subtitle: 'Ouverture, clôture, écarts',
                          onTap: () => context.go('/cash'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.calendar_month_rounded,
                          gradientColors: [
                            AppColors.blueLight,
                            AppColors.primaryLight,
                          ],
                          title: 'Réservations',
                          subtitle: 'Planning, clients et créneaux',
                          onTap: () => context.go('/booking'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.receipt_long_rounded,
                          gradientColors: [
                            AppColors.primaryLight,
                            Color(0xFF6366F1),
                          ],
                          title: 'Dépenses',
                          subtitle: 'Électricité, loyer, achats',
                          onTap: () => context.go('/expenses'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.local_offer_rounded,
                          gradientColors: [AppColors.pink, AppColors.amber],
                          title: 'Promotions',
                          subtitle: 'Happy Hour et réductions planifiées',
                          onTap: () => context.go('/promotions'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'SYSTÈME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppSurface(
                    borderRadius: 24,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        _buildMenuItem(
                          context,
                          icon: Icons.security_rounded,
                          gradientColors: [
                            Color(0xFF64748B),
                            Color(0xFF475569),
                          ],
                          title: 'Journal d\'activité',
                          subtitle: 'Qui a fait quoi, et quand',
                          onTap: () => context.go('/activity'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.settings_rounded,
                          gradientColors: [
                            Color(0xFF64748B),
                            Color(0xFF475569),
                          ],
                          title: 'Paramètres',
                          subtitle: 'Nom de la salle et fuseau horaire',
                          onTap: () => context.go('/settings'),
                        ),
                        _buildMenuItem(
                          context,
                          icon: Icons.archive_rounded,
                          gradientColors: [
                            AppColors.pink,
                            Color(0xFFDC2626),
                          ],
                          title: 'Archiver & Purger',
                          subtitle: 'Sauvegarder en JSON et réinitialiser l’historique',
                          onTap: () async {
                            final reset = await showDialog<bool>(
                              context: context,
                              builder: (context) => const ArchiveResetDialog(),
                            );
                            if (reset == true && context.mounted) {
                              context.go('/home');
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppButton(
                    label: 'Se déconnecter',
                    isGhost: true,
                    textColor: AppColors.red,
                    icon: const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: AppColors.red,
                    ),
                    onPressed: () async {
                      try {
                        await SupabaseAuthService.instance.signOut();
                        if (context.mounted) context.go('/login');
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                error is AuthFlowException
                                    ? error.message
                                    : 'La déconnexion a échoué. Réessayez.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'Ghost Gaming OS · v1.0.0',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppBottomNav(currentIndex: 4, isStaff: true),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required List<Color> gradientColors,
    required String title,
    required String subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: LinearGradient(colors: gradientColors),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xB2000000),
                    offset: Offset(0, 6),
                    blurRadius: 14,
                    spreadRadius: -4,
                  ),
                  BoxShadow(
                    color: Color(0x40FFFFFF),
                    offset: Offset(0, 1),
                    blurRadius: 0,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: AppColors.pink,
                  boxShadow: const [
                    BoxShadow(color: Color(0x99FF2D9B), blurRadius: 10),
                  ],
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF6A6B88)),
          ],
        ),
      ),
    );
  }
}
