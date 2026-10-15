import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../app/widgets/responsive_scaffold.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../sessions/data/session_dashboard_repository.dart';
import '../../sessions/domain/session_dashboard_models.dart';
import '../../sessions/presentation/session_dashboard_view_model.dart';
import '../../../core/data/venue_repository.dart';
import '../../notifications/domain/notification_permission_service.dart';

class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  late final SessionDashboardViewModel _viewModel;
  String? _pendingSessionId;
  bool _sessionJumpScheduled = false;
  final _sessionTargetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _viewModel = SessionDashboardViewModel(
      SessionDashboardRepository(Supabase.instance.client),
    )..initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificationPermissionService.checkAndPromptIfNeeded(context);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel.refresh();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _startSession([GamingPost? initialPost]) async {
    final snapshot = _viewModel.snapshot;
    if (snapshot == null) return;
    if (snapshot.games.isEmpty) {
      _showMessage(
        'Aucun jeu dans le catalogue. Ajoutez d’abord un jeu dans la section Jeux pour démarrer une session.',
      );
      return;
    }
    final availableGames = snapshot.games
        .where(
          (game) =>
              game.mode == 'match_based' || game.pricingUnit != 'per_match',
        )
        .toList();
    final availablePosts = startablePosts(snapshot.posts, availableGames);
    if (availablePosts.isEmpty || availableGames.isEmpty) {
      _showMessage(
        snapshot.posts.any(
                  (post) =>
                      post.status == 'available' || post.status == 'reserved',
                ) &&
                availableGames.isNotEmpty
            ? 'Aucun poste disponible pour les jeux configurés.'
            : availablePosts.isEmpty
            ? 'Aucun poste disponible. Ajoutez ou libérez un poste.'
            : 'Aucun jeu configuré avec une tarification compatible.',
      );
      return;
    }

    final result = await showDialog<_StartSessionSelection>(
      context: context,
      builder: (context) => _StartSessionDialog(
        initialPost: initialPost,
        posts: availablePosts,
        games: availableGames,
        customers: snapshot.customers,
      ),
    );
    if (result == null) return;
    await _viewModel.startSession(
      post: result.post,
      game: result.game,
      initialMinutes: result.initialMinutes,
      customerId: result.customerId,
    );
  }

  Future<void> _sessionAction(
    ActiveGamingSession session,
    String action,
  ) async {
    if (action == 'add_product') {
      await _addProductToSession(session);
      return;
    }
    if (action == 'pay_session') {
      await _paySession(session);
      return;
    }
    if (action == 'apply_promotion') {
      await _applyPromotion(session);
      return;
    }
    if (action == 'transfer_session') {
      await _transferSession(session);
      return;
    }
    if (action == 'end_session') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Terminer la session ?'),
          content: Text(
            'Le poste ${session.postName ?? ''} sera arrêté et la session passera au paiement.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Terminer'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    int? minutes;
    if (action == 'add_time') {
      minutes = await _askForMinutes();
      if (minutes == null) return;
    }
    await _viewModel.runSessionAction(session, action, minutes: minutes);
  }

  Future<void> _transferSession(ActiveGamingSession session) async {
    final snapshot = _viewModel.snapshot;
    if (snapshot == null) return;
    final targets = transferablePosts(snapshot.posts, session);
    if (targets.isEmpty) {
      _showMessage('Aucun autre poste disponible ou compatible pour le transfert.');
      return;
    }
    final target = await showDialog<GamingPost>(
      context: context,
      builder: (context) => _TransferSessionDialog(posts: targets),
    );
    if (target == null) return;
    await _viewModel.transferSession(session, target);
    if (mounted) {
      if (_viewModel.errorMessage != null) {
        _showMessage(_viewModel.errorMessage!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session transférée avec succès vers ${target.name} !'),
            backgroundColor: AppColors.green,
          ),
        );
      }
    }
  }

  Future<void> _addProductToSession(ActiveGamingSession session) async {
    final products = (_viewModel.snapshot?.products ?? [])
        .where((product) => product.isAvailable && product.stockQuantity > 0)
        .toList();
    if (products.isEmpty) {
      _showMessage('Aucun produit disponible en stock.');
      return;
    }
    final result = await showDialog<_SessionProductSelection>(
      context: context,
      builder: (context) => _SessionProductDialog(products: products),
    );
    if (result == null) return;
    await _viewModel.addProductToSession(
      session,
      result.product,
      result.quantity,
    );
  }

  Future<void> _paySession(ActiveGamingSession session) async {
    if (session.balanceDue <= 0) {
      final invoice = await _viewModel.paySession(session, const []);
      if (invoice != null && mounted) {
        _showMessage('Session clôturée sans paiement.');
      }
      return;
    }
    final lines = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => _SessionPaymentDialog(
        session: session,
        amountDue: session.balanceDue,
        hasCustomer: session.customerId != null,
        walletBalance: session.walletBalance,
        availableCredit: session.availableCredit,
        canManageCredit: _viewModel.snapshot?.canManageCredit == true,
      ),
    );
    if (lines == null) return;
    final invoice = await _viewModel.paySession(session, lines);
    if (invoice != null && mounted) {
      _showMessage(
        'Paiement confirmé · Facture n° ${invoice['invoice_number']} · '
        '${(invoice['total'] as num).toStringAsFixed(0)} DA',
      );
    }
  }

  Future<void> _applyPromotion(ActiveGamingSession session) async {
    final promotions = _viewModel.snapshot?.promotions ?? const [];
    if (promotions.isEmpty || session.promotionApplied) return;
    final promotion = await showDialog<SessionPromotion>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Appliquer une promotion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in promotions)
              ListTile(
                title: Text(item.name),
                subtitle: Text(
                  'Réduction de ${item.discountPercent.toStringAsFixed(0)} %',
                ),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (promotion == null) return;
    final result = await _viewModel.applyPromotion(session, promotion);
    if (result != null && mounted) {
      _showMessage(
        '${promotion.name} appliquée · '
        '${(result['discount_amount'] as num).toStringAsFixed(2)} DA de réduction.',
      );
    }
  }

  Future<int?> _askForMinutes() async {
    final controller = TextEditingController(text: '15');
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter du temps'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Durée en minutes',
            suffixText: 'min',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text);
              if (minutes != null && minutes > 0 && minutes <= 600) {
                Navigator.pop(context, minutes);
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _processStandaloneOrder(
    PendingStandaloneOrderRequest request, {
    required bool complete,
  }) async {
    String? method;
    if (complete) {
      method = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmer le paiement reçu'),
          content: Text(
            '${request.customerName} · ${request.productName} × '
            '${request.quantity} · ${request.total.toStringAsFixed(2)} DA\n\n'
            'Confirmez uniquement après avoir reçu le paiement au comptoir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cash'),
              child: const Text('Espèces reçues'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'card'),
              child: const Text('Carte reçue'),
            ),
          ],
        ),
      );
      if (method == null || !mounted) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Refuser cette commande ?'),
          content: const Text(
            'Le client sera informé que sa commande ne peut pas être traitée.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Retour'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Refuser'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final result = await _viewModel.processStandaloneOrder(
      request,
      complete: complete,
      paymentMethod: method,
    );
    if (!mounted) return;
    if (result == null) {
      _showMessage(
        _viewModel.errorMessage ?? 'La demande n’a pas pu être traitée.',
      );
    } else if (complete) {
      _showMessage(
        'Paiement enregistré · Facture n° ${result['invoice_number']} · '
        '${(result['total'] as num).toStringAsFixed(2)} DA.',
      );
    } else {
      _showMessage('Commande refusée. Le client en a été informé.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final requestedSessionId = GoRouterState.of(
      context,
    ).uri.queryParameters['sessionId'];
    _pendingSessionId ??= requestedSessionId;
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        final snapshot = _viewModel.snapshot;
        if (!_sessionJumpScheduled &&
            snapshot != null &&
            _pendingSessionId != null) {
          _sessionJumpScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final targetContext = _sessionTargetKey.currentContext;
            if (targetContext != null) {
              Scrollable.ensureVisible(
                targetContext,
                duration: const Duration(milliseconds: 350),
                alignment: 0.2,
              );
            } else {
              _showMessage(
                'La session de cette notification n’est plus active.',
              );
            }
          });
        }
        return ResponsiveScaffold(
          currentIndex: 0,
          isStaff: true,
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: RefreshIndicator(
                    onRefresh: _viewModel.refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                      children: [
                        _DashboardHeader(
                          venueName: snapshot?.venueName ?? 'Ghost Gaming',
                          onNotificationsTap: () =>
                              context.push('/notifications'),
                          onLogoutTap: () async {
                            try {
                              await Supabase.instance.client.auth.signOut();
                              if (context.mounted) context.go('/login');
                            } on AuthException {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'La déconnexion a échoué. Réessayez.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 18),
                        const _LoungeHero(),
                        if (!SupabaseConfig.isConfigured) ...[
                          const SizedBox(height: 16),
                          const _NoticeCard(
                            text:
                                'Configurez Supabase pour accéder aux données réelles de votre salle.',
                            color: AppColors.amber,
                          ),
                        ],
                        if (_viewModel.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _NoticeCard(
                            text: _viewModel.errorMessage!,
                            color: AppColors.red,
                            onRetry: _viewModel.refresh,
                          ),
                        ],
                        if (_viewModel.isLoading && snapshot == null) ...[
                          const SizedBox(height: 28),
                          const Center(child: CircularProgressIndicator()),
                        ] else if (snapshot != null) ...[
                          const SizedBox(height: 18),
                          _DashboardStats(
                            availableCount: snapshot.posts
                                .where((post) => post.status == 'available')
                                .length,
                            activeCount: snapshot.sessions
                                .where(
                                  (session) =>
                                      session.status == 'active' ||
                                      session.status == 'paused',
                                )
                                .length,
                          ),
                          const SizedBox(height: 20),
                          if (snapshot.games.isNotEmpty)
                            _FeaturedGameCarousel(games: snapshot.games),
                          const SizedBox(height: 20),
                          const _SectionHeading(
                            title: 'Actions rapides',
                            trailing: 'Gérer votre salle',
                          ),
                          const SizedBox(height: 12),
                          if (MediaQuery.of(context).size.width < 900) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickActionCard(
                                    icon: Icons.sports_esports_rounded,
                                    title: 'Postes',
                                    subtitle: 'Gérer les stations',
                                    color: AppColors.blueLight,
                                    onTap: () => context.go('/posts'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _QuickActionCard(
                                    icon: Icons.shopping_bag_rounded,
                                    title: 'Boutique',
                                    subtitle: 'Boissons & snacks',
                                    color: AppColors.primaryLight,
                                    onTap: () => context.go('/inventory'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _QuickActionCard(
                              icon: Icons.calendar_month_rounded,
                              title: 'Réservations',
                              subtitle: 'Voir le planning et les demandes',
                              color: AppColors.amber,
                              onTap: () => context.go('/booking'),
                            ),
                            const SizedBox(height: 10),
                            _QuickActionCard(
                              icon: Icons.point_of_sale_rounded,
                              title: 'Caisse',
                              subtitle: 'Ouvrir ou clôturer un service',
                              color: AppColors.green,
                              onTap: () => context.go('/cash'),
                            ),
                            const SizedBox(height: 10),
                            _QuickActionCard(
                              icon: Icons.receipt_long_rounded,
                              title: 'Factures',
                              subtitle: 'Consulter les 100 dernières factures',
                              color: AppColors.primaryLight,
                              onTap: () => context.go('/invoices'),
                            ),
                            if (snapshot.canManagePromotions) ...[
                              const SizedBox(height: 10),
                              _QuickActionCard(
                                icon: Icons.local_offer_outlined,
                                title: 'Promotions',
                                subtitle:
                                    'Programmer et appliquer des réductions',
                                color: AppColors.pink,
                                onTap: () => context.go('/promotions'),
                              ),
                            ],
                            const SizedBox(height: 10),
                            _QuickActionCard(
                              icon: Icons.card_giftcard_rounded,
                              title: 'Fidélité',
                              subtitle: 'Traiter les demandes de récompense',
                              color: AppColors.pink,
                              onTap: () => context.go('/loyalty'),
                            ),
                            const SizedBox(height: 10),
                            _QuickActionCard(
                              icon: Icons.card_membership_rounded,
                              title: 'Formules clients',
                              subtitle: 'Vendre des minutes et produits prépayés',
                              color: AppColors.green,
                              onTap: () => context.go('/programs'),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickActionCard(
                                    icon: Icons.sports_esports_rounded,
                                    title: 'Postes',
                                    subtitle: 'Gérer les stations',
                                    color: AppColors.blueLight,
                                    onTap: () => context.go('/posts'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _QuickActionCard(
                                    icon: Icons.shopping_bag_rounded,
                                    title: 'Boutique',
                                    subtitle: 'Boissons & snacks',
                                    color: AppColors.primaryLight,
                                    onTap: () => context.go('/inventory'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickActionCard(
                                    icon: Icons.calendar_month_rounded,
                                    title: 'Réservations',
                                    subtitle: 'Voir le planning et les demandes',
                                    color: AppColors.amber,
                                    onTap: () => context.go('/booking'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _QuickActionCard(
                                    icon: Icons.point_of_sale_rounded,
                                    title: 'Caisse',
                                    subtitle: 'Ouvrir ou clôturer un service',
                                    color: AppColors.green,
                                    onTap: () => context.go('/cash'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _QuickActionCard(
                                    icon: Icons.receipt_long_rounded,
                                    title: 'Factures',
                                    subtitle: 'Consulter les 100 dernières factures',
                                    color: AppColors.primaryLight,
                                    onTap: () => context.go('/invoices'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (snapshot.canManagePromotions)
                                  Expanded(
                                    child: _QuickActionCard(
                                      icon: Icons.local_offer_outlined,
                                      title: 'Promotions',
                                      subtitle:
                                          'Programmer et appliquer des réductions',
                                      color: AppColors.pink,
                                      onTap: () => context.go('/promotions'),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: _QuickActionCard(
                                      icon: Icons.card_giftcard_rounded,
                                      title: 'Fidélité',
                                      subtitle: 'Traiter les demandes de récompense',
                                      color: AppColors.pink,
                                      onTap: () => context.go('/loyalty'),
                                    ),
                                  ),
                              ],
                            ),
                            if (snapshot.canManagePromotions) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _QuickActionCard(
                                      icon: Icons.card_giftcard_rounded,
                                      title: 'Fidélité',
                                      subtitle: 'Traiter les demandes de récompense',
                                      color: AppColors.pink,
                                      onTap: () => context.go('/loyalty'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _QuickActionCard(
                                      icon: Icons.card_membership_rounded,
                                      title: 'Formules clients',
                                      subtitle: 'Vendre des minutes et produits prépayés',
                                      color: AppColors.green,
                                      onTap: () => context.go('/programs'),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _QuickActionCard(
                                      icon: Icons.card_membership_rounded,
                                      title: 'Formules clients',
                                      subtitle: 'Vendre des minutes et produits prépayés',
                                      color: AppColors.green,
                                      onTap: () => context.go('/programs'),
                                    ),
                                  ),
                                  const Expanded(child: SizedBox()),
                                ],
                              ),
                            ],
                          ],
                          if (snapshot.requests.isEmpty &&
                              snapshot.standaloneOrderRequests.isEmpty) ...[
                            const SizedBox(height: 24),
                            const _SectionHeading(
                              title: 'Demandes en attente',
                              trailing: 'Aucune demande',
                            ),
                            const SizedBox(height: 12),
                            const _EmptyState(
                              icon: Icons.notifications_none_rounded,
                              message: 'Aucune demande pour le moment.',
                            ),
                          ],
                          if (snapshot.requests.isNotEmpty ||
                              snapshot.standaloneOrderRequests.isNotEmpty) ...[
                            const SizedBox(height: 26),
                            const _SectionHeading(
                              title: 'Demandes en attente',
                              trailing: 'À traiter',
                            ),
                            const SizedBox(height: 12),
                            ...snapshot.standaloneOrderRequests.map(
                              (request) => _StandaloneOrderRequestCard(
                                request: request,
                                isWorking: _viewModel.isWorking,
                                onComplete: () => _processStandaloneOrder(
                                  request,
                                  complete: true,
                                ),
                                onReject: () => _processStandaloneOrder(
                                  request,
                                  complete: false,
                                ),
                              ),
                            ),
                            ...snapshot.requests.map(
                              (request) => _RequestCard(
                                request: request,
                                isWorking: _viewModel.isWorking,
                                onDecision: (approve) => _viewModel
                                    .decideRequest(request, approve: approve),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          AppSurface(
                            borderRadius: 22,
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(15),
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                  ),
                                  child: const Icon(
                                    Icons.sports_esports_rounded,
                                    color: AppColors.primaryLight,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Gestion des postes',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${snapshot.posts.length} poste${snapshot.posts.length == 1 ? '' : 's'} · ${snapshot.sessions.length} session${snapshot.sessions.length == 1 ? '' : 's'} active${snapshot.sessions.length == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: () => context.go('/posts'),
                                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                  label: const Text('Ouvrir'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                      ],
                    ),
                  ),
                ),
              );
      },
    );
  }
}

ActiveGamingSession? _sessionForPost(
  List<ActiveGamingSession> sessions,
  String postId,
) {
  for (final session in sessions) {
    if (session.postId == postId) return session;
  }
  return null;
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.venueName,
    required this.onNotificationsTap,
    required this.onLogoutTap,
  });

  final String venueName;
  final VoidCallback onNotificationsTap;
  final VoidCallback onLogoutTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AppSurface(
          borderRadius: 15,
          padding: EdgeInsets.all(10),
          onTap: onNotificationsTap,
          child: Icon(
            Icons.notifications_none_rounded,
            color: AppColors.text,
            size: 22,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppBrandLogo(fontSize: 17),
            Text(
              venueName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: AppColors.muted),
            ),
          ],
        ),
        AppSurface(
          borderRadius: 15,
          padding: const EdgeInsets.all(10),
          onTap: onLogoutTap,
          child: const Icon(Icons.logout_rounded, size: 20),
        ),
      ],
    );
  }
}

class _LoungeHero extends StatelessWidget {
  const _LoungeHero();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: Container(
      height: 173,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2C1B5C), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x666E28DC),
            offset: Offset(0, 16),
            blurRadius: 34,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/hero_skull.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.90),
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.20),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xE6281845),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0x8C8C5AE6)),
                  ),
                  child: const Text(
                    'PS4 & PS5 LOUNGE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                const Text(
                  'Ready to',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const Text(
                  'play?',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: AppColors.pink,
                    shadows: [Shadow(color: AppColors.pink, blurRadius: 18)],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xF2140E2C),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0x80965AF0)),
                  ),
                  child: const Text(
                    'FORFAIT PAR MATCH · DA',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70),
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      Text(
        trailing,
        style: const TextStyle(fontSize: 12, color: AppColors.pink),
      ),
    ],
  );
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppSurface(
    onTap: onTap,
    borderRadius: 24,
    padding: const EdgeInsets.all(16),
    child: SizedBox(
      height: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 28, color: color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _FeaturedGameCarousel extends StatefulWidget {
  const _FeaturedGameCarousel({required this.games});

  final List<CatalogGame> games;

  @override
  State<_FeaturedGameCarousel> createState() => _FeaturedGameCarouselState();
}

class _FeaturedGameCarouselState extends State<_FeaturedGameCarousel>
    with WidgetsBindingObserver {
  late final PageController _controller;
  Timer? _autoplay;
  Timer? _resumeTimer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = PageController(viewportFraction: 0.94);
    _startAutoplay();
  }

  @override
  void didUpdateWidget(covariant _FeaturedGameCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.games.length != oldWidget.games.length &&
        _page >= widget.games.length) {
      _page = 0;
      _controller.jumpToPage(0);
    }
  }

  void _startAutoplay() {
    _autoplay?.cancel();
    if (widget.games.length < 2 ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _autoplay = Timer.periodic(const Duration(milliseconds: 4500), (_) {
      if (!_controller.hasClients) return;
      final next = (_page + 1) % widget.games.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _pauseAutoplay() {
    _autoplay?.cancel();
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 8), _startAutoplay);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoplay();
    } else {
      _autoplay?.cancel();
      _resumeTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoplay?.cancel();
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 195,
        child: GestureDetector(
          onPanDown: (_) => _pauseAutoplay(),
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.games.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) {
              final game = widget.games[index];
              final imageUrl = game.imageUrl;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(27),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(27),
                      border: Border.all(color: const Color(0xFF2A1C52)),
                      gradient: imageUrl == null || imageUrl.isEmpty
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF1A1230),
                                Color(0xFF0C0C1C),
                                Color(0xFF3A1466),
                              ],
                            )
                          : null,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty) ...[
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.3),
                                  Colors.black.withValues(alpha: 0.8),
                                ],
                              ),
                            ),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.all(19),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                index == 0 ? 'JEU À LA UNE' : 'JEU DISPONIBLE',
                                style: const TextStyle(
                                  color: AppColors.pink,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                game.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF7A2FD6), AppColors.primary],
                                      ),
                                    ),
                                    child: Text(
                                      '${game.price.toStringAsFixed(0)} DA / ${game.mode == 'match_based' ? 'Match' : 'Session'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (imageUrl == null || imageUrl.isEmpty)
                                    const Icon(
                                      Icons.sports_esports_rounded,
                                      size: 32,
                                      color: AppColors.blueLight,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.games.length, (index) {
          final active = index == _page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 24 : 8,
            height: 6,
            decoration: BoxDecoration(
              color: active ? AppColors.pink : const Color(0xFF3A3558),
              borderRadius: BorderRadius.circular(4),
              boxShadow: active
                  ? const [BoxShadow(color: AppColors.pink, blurRadius: 8)]
                  : null,
            ),
          );
        }),
      ),
    ],
  );
}

class _DashboardStats extends StatelessWidget {
  const _DashboardStats({
    required this.availableCount,
    required this.activeCount,
  });

  final int availableCount;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Postes libres',
            value: '$availableCount Dispo',
            icon: Icons.circle,
            color: AppColors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'Matchs actifs',
            value: '$activeCount En Match',
            icon: Icons.circle,
            color: AppColors.pink,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 58,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
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
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    super.key,
    required this.post,
    required this.session,
    required this.isWorking,
    required this.promotions,
    required this.canGiveDiscount,
    required this.onStart,
    required this.onAction,
  });

  final GamingPost post;
  final ActiveGamingSession? session;
  final bool isWorking;
  final List<SessionPromotion> promotions;
  final bool canGiveDiscount;
  final VoidCallback onStart;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final status = session?.status ?? post.status;
    final hasSession = session != null;
    final statusColor = switch (status) {
      'active' || 'playing' => AppColors.green,
      'paused' => AppColors.amber,
      'waiting_payment' => AppColors.pink,
      'maintenance' || 'offline' => AppColors.red,
      _ => AppColors.blueLight,
    };
    return AppSurface(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.sports_esports_rounded,
                  size: 18,
                  color: AppColors.primaryLight,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${post.device.toUpperCase()} · Poste ${post.number}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: statusColor.withValues(alpha: 0.15),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasSession) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surface1.withValues(alpha: 0.5),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session!.game?.name ?? 'Jeu',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                        child: Text(
                          session!.game?.mode == 'match_based'
                              ? 'Matchs'
                              : 'Temps',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline_rounded,
                        size: 14,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          session!.customerName ?? 'Client sans compte',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.bg.withValues(alpha: 0.7),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: AppColors.blueLight,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Restant : ',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                        Expanded(
                          child: _StaffSessionCountdown(
                            session: session!,
                            isMatchBased:
                                session!.game?.mode == 'match_based',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Jeux: ${session!.gamingTotal.toStringAsFixed(0)} DA · Bar: ${session!.productsTotal.toStringAsFixed(0)} DA',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.muted,
                        ),
                      ),
                      Text(
                        'Total: ${(session!.gamingTotal + session!.productsTotal).toStringAsFixed(0)} DA',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.pink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 22,
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surface1.withValues(alpha: 0.3),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.videogame_asset_off_outlined,
                    size: 32,
                    color: AppColors.muted,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Poste libre',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          isWorking ||
                              (post.status != 'available' &&
                                  post.status != 'reserved')
                          ? null
                          : onStart,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Démarrer une session'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasSession) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (session!.status == 'waiting_payment') ...[
                  _ActionButton(
                    label: session!.balanceDue > 0
                        ? 'Encaisser ${session!.balanceDue.toStringAsFixed(0)} DA'
                        : 'Clôturer sans paiement',
                    icon: Icons.payments_outlined,
                    enabled: !isWorking,
                    onPressed: () => onAction('pay_session'),
                  ),
                  if (canGiveDiscount &&
                      promotions.isNotEmpty &&
                      !session!.promotionApplied)
                    _ActionButton(
                      label: 'Promotion',
                      icon: Icons.local_offer_outlined,
                      enabled: !isWorking,
                      onPressed: () => onAction('apply_promotion'),
                    ),
                ] else ...[
                  _ActionButton(
                    label: '+ Produit',
                    icon: Icons.add_shopping_cart_rounded,
                    enabled: !isWorking && session!.status == 'active',
                    onPressed: () => onAction('add_product'),
                  ),
                  if (session!.game?.mode == 'match_based')
                    _ActionButton(
                      label: '+ Match',
                      icon: Icons.sports_esports_rounded,
                      enabled: !isWorking && session!.status == 'active',
                      onPressed: () => onAction('add_match'),
                    )
                  else
                    _ActionButton(
                      label: '+ Temps',
                      icon: Icons.more_time_rounded,
                      enabled: !isWorking && session!.status == 'active',
                      onPressed: () => onAction('add_time'),
                    ),
                  if (session!.status == 'paused' ||
                      session!.status == 'active')
                    _ActionButton(
                      label: session!.status == 'paused'
                          ? 'Reprendre'
                          : 'Pause',
                      icon: session!.status == 'paused'
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      enabled: !isWorking,
                      onPressed: () => onAction(
                        session!.status == 'paused'
                            ? 'resume_session'
                            : 'pause_session',
                      ),
                    ),
                  if (session!.status == 'paused' ||
                      session!.status == 'active')
                    _ActionButton(
                      label: 'Transférer',
                      icon: Icons.swap_horiz_rounded,
                      enabled: !isWorking,
                      onPressed: () => onAction('transfer_session'),
                    ),
                  if (session!.status == 'paused' ||
                      session!.status == 'active')
                    _ActionButton(
                      label: 'Terminer',
                      icon: Icons.stop_rounded,
                      enabled: !isWorking,
                      onPressed: () => onAction('end_session'),
                    ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StaffSessionCountdown extends StatefulWidget {
  const _StaffSessionCountdown({
    required this.session,
    required this.isMatchBased,
  });

  final ActiveGamingSession session;
  final bool isMatchBased;

  @override
  State<_StaffSessionCountdown> createState() => _StaffSessionCountdownState();
}

class _StaffSessionCountdownState extends State<_StaffSessionCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _StaffSessionCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.status != widget.session.status) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.session.status == 'active' &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      setState(() {});
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _formatDuration(
      widget.session.remainingSeconds(DateTime.now()),
    );
    return Text(
      widget.isMatchBased
          ? 'Matchs : ${widget.session.matchCount} · $remaining restantes'
          : '$remaining restantes',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: AppColors.blueLight),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 10)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isWorking,
    required this.onDecision,
  });

  final PendingSessionRequest request;
  final bool isWorking;
  final ValueChanged<bool> onDecision;

  @override
  Widget build(BuildContext context) {
    final detail = switch (request.type) {
      'match' => 'demande ${request.payload['qty'] ?? 1} match',
      'time' => 'demande ${request.payload['minutes'] ?? 0} minutes',
      'checkout' => 'demande la clôture de sa session',
      _ => 'a envoyé une demande',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppSurface(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              color: AppColors.amber,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${request.postName} · ${request.customerName} $detail',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            IconButton(
              tooltip: 'Refuser',
              onPressed: isWorking ? null : () => onDecision(false),
              icon: const Icon(Icons.close_rounded, color: AppColors.red),
            ),
            IconButton(
              tooltip: 'Accepter',
              onPressed: isWorking ? null : () => onDecision(true),
              icon: const Icon(Icons.check_rounded, color: AppColors.green),
            ),
          ],
        ),
      ),
    );
  }
}

class _StandaloneOrderRequestCard extends StatelessWidget {
  const _StandaloneOrderRequestCard({
    required this.request,
    required this.isWorking,
    required this.onComplete,
    required this.onReject,
  });

  final PendingStandaloneOrderRequest request;
  final bool isWorking;
  final VoidCallback onComplete;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, color: AppColors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${request.customerName} · ${request.productName} × '
                  '${request.quantity}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${request.total.toStringAsFixed(2)} DA',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Commande hors session · encaissez au comptoir avant de confirmer.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isWorking ? null : onReject,
                child: const Text(
                  'Refuser',
                  style: TextStyle(color: AppColors.red),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: isWorking ? null : onComplete,
                icon: const Icon(Icons.point_of_sale_rounded, size: 16),
                label: const Text('Paiement reçu'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.text, required this.color, this.onRetry});

  final String text;
  final Color color;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: 16,
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
          if (onRetry != null)
            IconButton(
              tooltip: 'Réessayer',
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, color: color),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: 18,
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _SessionProductSelection {
  const _SessionProductSelection({
    required this.product,
    required this.quantity,
  });

  final SessionProduct product;
  final int quantity;
}

class _SessionProductDialog extends StatefulWidget {
  const _SessionProductDialog({required this.products});

  final List<SessionProduct> products;

  @override
  State<_SessionProductDialog> createState() => _SessionProductDialogState();
}

class _SessionProductDialogState extends State<_SessionProductDialog> {
  late SessionProduct _product = widget.products.first;
  final _quantity = TextEditingController(text: '1');

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quantity = int.tryParse(_quantity.text) ?? 0;
    return AlertDialog(
      title: const Text('Ajouter un produit à la session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<SessionProduct>(
            initialValue: _product,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Produit'),
            items: widget.products
                .map(
                  (product) => DropdownMenuItem(
                    value: product,
                    child: Text(
                      '${product.name} · ${product.price.toStringAsFixed(0)} DA'
                      ' · stock ${product.stockQuantity}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (product) {
              if (product != null) setState(() => _product = product);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Quantité',
              helperText: 'Stock disponible : ${_product.stockQuantity}',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total : ${(quantity * _product.price).toStringAsFixed(0)} DA',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: quantity > 0 && quantity <= _product.stockQuantity
              ? () => Navigator.pop(
                  context,
                  _SessionProductSelection(
                    product: _product,
                    quantity: quantity,
                  ),
                )
              : null,
          child: const Text('Ajouter à la facture'),
        ),
      ],
    );
  }
}

class _SessionPaymentDialog extends StatefulWidget {
  const _SessionPaymentDialog({
    required this.session,
    required this.amountDue,
    required this.hasCustomer,
    required this.walletBalance,
    required this.availableCredit,
    required this.canManageCredit,
  });

  final ActiveGamingSession session;
  final double amountDue;
  final bool hasCustomer;
  final double walletBalance;
  final double availableCredit;
  final bool canManageCredit;

  @override
  State<_SessionPaymentDialog> createState() => _SessionPaymentDialogState();
}

class _SessionPaymentDialogState extends State<_SessionPaymentDialog> {
  int _selectedMode = 0; // 0 = Cash/Card/Wallet, 1 = Debt/Credit
  late final _cash = TextEditingController(
    text: widget.amountDue.toStringAsFixed(2),
  );
  final _card = TextEditingController(text: '0');
  final _wallet = TextEditingController(text: '0');
  final _credit = TextEditingController(text: '0');
  final _debtCustomerNameController = TextEditingController();
  final _debtCustomerPhoneController = TextEditingController();
  bool _creatingCustomer = false;

  @override
  void initState() {
    super.initState();
    _debtCustomerNameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cash.dispose();
    _card.dispose();
    _wallet.dispose();
    _credit.dispose();
    _debtCustomerNameController.dispose();
    _debtCustomerPhoneController.dispose();
    super.dispose();
  }

  void _onModeChanged(int mode) {
    setState(() {
      _selectedMode = mode;
      final balance = widget.amountDue;
      if (mode == 1) {
        _cash.text = '0';
        _card.text = '0';
        _wallet.text = '0';
        _credit.text = balance.toStringAsFixed(2);
      } else {
        _cash.text = balance.toStringAsFixed(2);
        _card.text = '0';
        _wallet.text = '0';
        _credit.text = '0';
      }
    });
  }

  double _amount(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  double _entered(String key) {
    final text = switch (key) {
      'cash' => _cash.text,
      'card' => _card.text,
      'wallet' => _wallet.text,
      'credit' => _credit.text,
      _ => '',
    }.trim().replaceAll(',', '.');
    return double.tryParse(text) ?? 0;
  }

  Future<void> _submitPaymentOrDebt() async {
    final balance = widget.amountDue;
    if (_selectedMode == 1 && widget.session.customerId == null) {
      final name = _debtCustomerNameController.text.trim();
      if (name.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saisissez le nom du client pour la dette.'),
          ),
        );
        return;
      }
      setState(() => _creatingCustomer = true);
      try {
        final client = Supabase.instance.client;
        final venue = await VenueRepository(client).currentVenue();
        if (!mounted) return;
        final venueId = venue.id;

        final existingCustomers = await client
            .from('customers')
            .select('id, full_name, phone')
            .eq('venue_id', venueId)
            .ilike('full_name', name)
            .limit(1);
        if (!mounted) return;

        String? customerId;
        if (existingCustomers.isNotEmpty) {
          final existing = existingCustomers.first;
          if (!mounted) return;
          setState(() => _creatingCustomer = false);
          if (!mounted) return;
          final action = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Client existant détecté'),
              content: Text(
                'Un client nommé "${existing['full_name']}" existe déjà dans le système (Tél: ${existing['phone'] ?? 'N/A'}). Voulez-vous rattacher cette dette à son compte existant ?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'new'),
                  child: const Text('Créer un nouveau'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'existing'),
                  child: const Text('Rattacher au compte'),
                ),
              ],
            ),
          );

          if (!mounted) return;
          if (action == 'cancel' || action == null) {
            return;
          }
          if (action == 'existing') {
            customerId = existing['id'] as String;
          }
          if (!mounted) return;
          setState(() => _creatingCustomer = true);
        }

        if (customerId == null) {
          final newCust = await client
              .from('customers')
              .insert({
                'venue_id': venueId,
                'full_name': name,
                'phone': _debtCustomerPhoneController.text.trim().isEmpty
                    ? null
                    : _debtCustomerPhoneController.text.trim(),
              })
              .select('id')
              .single();
          if (!mounted) return;
          customerId = newCust['id'] as String;
        }

        await client
            .from('sessions')
            .update({'customer_id': customerId})
            .eq('id', widget.session.id);
        if (!mounted) return;
      } catch (e) {
        debugPrint('Gestion client pour dette : $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
        if (!mounted) return;
        setState(() => _creatingCustomer = false);
        return;
      } finally {
        if (mounted) setState(() => _creatingCustomer = false);
      }
    }

    final lines = <Map<String, dynamic>>[];
    for (final method in ['cash', 'card', 'wallet', 'credit']) {
      final amount = _entered(method);
      if (amount > 0) {
        lines.add({'method': method, 'amount': amount});
      }
    }
    if (lines.isEmpty && _selectedMode == 1) {
      lines.add({'method': 'credit', 'amount': balance});
    }
    if (!mounted) return;
    Navigator.pop(context, lines);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final balance = widget.amountDue;
    final cash = _amount(_cash);
    final card = _amount(_card);
    final wallet = _amount(_wallet);
    final credit = _amount(_credit);
    final total = cash + card + wallet + credit;
    final hasCustomer = session.customerId != null;
    final needsDebtName = _selectedMode == 1 && !hasCustomer;
    final debtNameValid =
        !needsDebtName || _debtCustomerNameController.text.trim().isNotEmpty;
    final valid = (total - balance).abs() < 0.01 && debtNameValid;

    return AlertDialog(
      title: Text('Règlement · ${session.postName ?? 'Session'}'),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Reste à payer : ${balance.toStringAsFixed(2)} DA',
                    style: const TextStyle(
                      color: AppColors.pink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        selected: _selectedMode == 0,
                        onSelected: (_) => _onModeChanged(0),
                        avatar: const Icon(Icons.payments_outlined, size: 16),
                        label: const Text('Comptant (Cash)', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        selected: _selectedMode == 1,
                        onSelected: (_) => _onModeChanged(1),
                        selectedColor: AppColors.pink.withValues(alpha: 0.25),
                        avatar: const Icon(Icons.bookmark_add_outlined, size: 16, color: AppColors.pink),
                        label: const Text('En Dette (Crédit)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_selectedMode == 0) ...[
                  TextField(
                    controller: _cash,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Espèces',
                      suffixText: 'DA',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _card,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Carte',
                      suffixText: 'DA',
                    ),
                  ),
                  if (widget.hasCustomer) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _wallet,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText:
                            'Portefeuille (${widget.walletBalance.toStringAsFixed(2)} DA)',
                        suffixText: 'DA',
                      ),
                    ),
                  ],
                  if (widget.hasCustomer &&
                      widget.canManageCredit &&
                      widget.availableCredit > 0) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _credit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText:
                            'Crédit disponible (${widget.availableCredit.toStringAsFixed(2)} DA)',
                        suffixText: 'DA',
                      ),
                    ),
                  ],
                ] else ...[
                  if (hasCustomer) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.pink.withValues(alpha: 0.15),
                        border: Border.all(color: AppColors.pink.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.bookmark_add_rounded, color: AppColors.pink),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Le montant de ${balance.toStringAsFixed(2)} DA sera enregistré comme dette sur le compte de ${session.customerName}.',
                              style: const TextStyle(fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.surface1.withValues(alpha: 0.5),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Saisissez le nom du client pour enregistrer la dette :',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _debtCustomerNameController,
                            decoration: const InputDecoration(
                              labelText: 'Nom et prénom du client',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _debtCustomerPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Téléphone (facultatif)',
                              isDense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                Text(
                  'Montant validé : ${total.toStringAsFixed(2)} / ${balance.toStringAsFixed(2)} DA',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: valid ? AppColors.green : AppColors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: (_creatingCustomer || !valid) ? null : _submitPaymentOrDebt,
          child: Text(_selectedMode == 1 ? 'Enregistrer la Dette' : 'Valider le paiement'),
        ),
      ],
    );
  }
}

class _StartSessionSelection {
  const _StartSessionSelection({
    required this.post,
    required this.game,
    this.customerId,
    this.initialMinutes,
  });

  final GamingPost post;
  final CatalogGame game;
  final String? customerId;
  final int? initialMinutes;
}

class _TransferSessionDialog extends StatefulWidget {
  const _TransferSessionDialog({required this.posts});

  final List<GamingPost> posts;

  @override
  State<_TransferSessionDialog> createState() => _TransferSessionDialogState();
}

class _TransferSessionDialogState extends State<_TransferSessionDialog> {
  late GamingPost _post = widget.posts.first;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Transférer la session'),
    content: DropdownButtonFormField<GamingPost>(
      initialValue: _post,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Nouveau poste'),
      items: widget.posts
          .map(
            (post) => DropdownMenuItem(
              value: post,
              child: Text(
                '${post.name} · ${post.device.toUpperCase()}'
                '${post.status == 'reserved' ? ' · Réservé' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (post) {
        if (post != null) setState(() => _post = post);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _post),
        child: const Text('Transférer'),
      ),
    ],
  );
}

class _StartSessionDialog extends StatefulWidget {
  const _StartSessionDialog({
    this.initialPost,
    required this.posts,
    required this.games,
    required this.customers,
  });

  final GamingPost? initialPost;
  final List<GamingPost> posts;
  final List<CatalogGame> games;
  final List<VenueCustomer> customers;

  @override
  State<_StartSessionDialog> createState() => _StartSessionDialogState();
}

class _StartSessionDialogState extends State<_StartSessionDialog> {
  late GamingPost _post;
  late CatalogGame _game;
  String? _customerId;
  final _minutesController = TextEditingController(text: '60');
  int _selectedFootballMatchMins = 10;
  int _footballMatchCount = 1;

  @override
  void initState() {
    super.initState();
    _post =
        (widget.initialPost != null && widget.posts.contains(widget.initialPost))
            ? widget.initialPost!
            : widget.posts.first;
    final compatible = _gamesForPost(_post);
    _game = compatible.isNotEmpty ? compatible.first : widget.games.first;
    _selectedFootballMatchMins = _game.matchMinutes ?? 10;
    _minutesController.text = (_selectedFootballMatchMins * _footballMatchCount).toString();
  }

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compatibleGames = _gamesForPost(_post);
    final gameIsAvailable = compatibleGames.isNotEmpty;
    final isMatchBased = _game.mode == 'match_based';
    return AlertDialog(
      title: const Text('Nouvelle session'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<GamingPost>(
                initialValue: _post,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Poste'),
                items: widget.posts
                    .map(
                      (post) => DropdownMenuItem(
                        value: post,
                        child: Text('${post.name} · ${post.device.toUpperCase()}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _post = value;
                      final compatible = _gamesForPost(value);
                      if (compatible.isNotEmpty && !value.supportsGame(_game.id)) {
                        _game = compatible.first;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 14),
              if (!gameIsAvailable)
                const Text(
                  'Aucun jeu compatible avec ce poste. Modifiez sa configuration.',
                  style: TextStyle(color: AppColors.red),
                )
              else
                DropdownButtonFormField<CatalogGame>(
                  initialValue: compatibleGames.contains(_game)
                      ? _game
                      : compatibleGames.first,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Jeu'),
                  items: compatibleGames
                      .map(
                        (game) => DropdownMenuItem(
                          value: game,
                          child: Text(
                            '${game.name} · ${_post.priceFor(game).toStringAsFixed(2)} DA',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _game = value;
                        _selectedFootballMatchMins = value.matchMinutes ?? 10;
                        _minutesController.text = (_selectedFootballMatchMins * _footballMatchCount).toString();
                      });
                    }
                  },
                ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: _customerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Client (facultatif)'),
                items: [
                  const DropdownMenuItem<String?>(
                    child: Text('Client sans compte'),
                  ),
                  ...widget.customers.map(
                    (customer) => DropdownMenuItem<String?>(
                      value: customer.id,
                      child: Text(customer.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _customerId = value),
              ),
              if (gameIsAvailable && !isMatchBased) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _minutesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Durée initiale',
                    suffixText: 'minutes',
                  ),
                ),
              ] else if (gameIsAvailable && isMatchBased) ...[
                const SizedBox(height: 16),
                const Text(
                  'Durée du Match (6, 8, 10, 16 min)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [6, 8, 10, 16].map((mins) {
                    final isSelected = _selectedFootballMatchMins == mins;
                    final tierPrice = _game.pricingTiers[mins.toString()] ?? _game.price;
                    return ChoiceChip(
                      label: Text('$mins min (${tierPrice.toStringAsFixed(0)} DA)'),
                      selected: isSelected,
                      selectedColor: AppColors.pink,
                      backgroundColor: AppColors.surface2,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.muted,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                      ),
                      onSelected: (_) => setState(() {
                        _selectedFootballMatchMins = mins;
                        _minutesController.text = (mins * _footballMatchCount).toString();
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Nombre de Matchs (${_selectedFootballMatchMins}m) :',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => setState(() {
                              if (_footballMatchCount > 1) {
                                _footballMatchCount--;
                                _minutesController.text = (_selectedFootballMatchMins * _footballMatchCount).toString();
                              }
                            }),
                            icon: const Icon(Icons.remove_circle_outline, size: 20, color: AppColors.primaryLight),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('$_footballMatchCount', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _footballMatchCount++;
                              _minutesController.text = (_selectedFootballMatchMins * _footballMatchCount).toString();
                            }),
                            icon: const Icon(Icons.add_circle_outline, size: 20, color: AppColors.primaryLight),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: !gameIsAvailable
              ? null
              : () {
                  final minutes = int.tryParse(_minutesController.text);
                  Navigator.pop(
                    context,
                    _StartSessionSelection(
                      post: _post,
                      game: _game,
                      customerId: _customerId,
                      initialMinutes: minutes ?? (_selectedFootballMatchMins * _footballMatchCount),
                    ),
                  );
                },
          child: const Text('Démarrer'),
        ),
      ],
    );
  }

  List<CatalogGame> _gamesForPost(GamingPost post) => widget.games
      .where((game) => post.supportsGame(game.id))
      .toList(growable: false);
}

String _statusLabel(String status) => switch (status) {
  'available' => 'DISPONIBLE',
  'reserved' => 'RÉSERVÉ',
  'starting' => 'DÉMARRAGE',
  'playing' || 'active' => 'EN COURS',
  'paused' => 'EN PAUSE',
  'waiting_payment' => 'PAIEMENT',
  'maintenance' => 'MAINTENANCE',
  'offline' => 'HORS LIGNE',
  _ => status.toUpperCase(),
};

String _formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  return [
    hours.toString().padLeft(2, '0'),
    minutes.toString().padLeft(2, '0'),
    remainingSeconds.toString().padLeft(2, '0'),
  ].join(':');
}
