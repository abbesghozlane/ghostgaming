import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../app/widgets/responsive_scaffold.dart';
import '../../../core/utils/venue_time_zone.dart';
import '../data/customer_repository.dart';
import '../domain/customer_order_policy.dart';
import '../domain/customer_session_selection.dart';
import '../../notifications/domain/notification_permission_service.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  late final CustomerRepository _repository;
  CustomerHomeSnapshot? _snapshot;
  RealtimeChannel? _userChannel;
  final List<RealtimeChannel> _sessionChannels = [];
  List<String> _sessionIds = const [];
  RealtimeChannel? _catalogChannel;
  RealtimeChannel? _inventoryChannel;
  RealtimeChannel? _programChannel;
  Timer? _refreshTimer;
  String? _selectedSessionId;
  String? _venueId;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _repository = CustomerRepository(Supabase.instance.client);
    _subscribeToUserNotifications();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificationPermissionService.checkAndPromptIfNeeded(context);
      }
    });
  }

  @override
  void dispose() {
    _userChannel?.unsubscribe();
    for (final channel in _sessionChannels) {
      channel.unsubscribe();
    }
    _catalogChannel?.unsubscribe();
    _inventoryChannel?.unsubscribe();
    _programChannel?.unsubscribe();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snapshot = await _repository.loadHome();
      if (!mounted) return;
      final sessionIds = snapshot.sessions
          .map((session) => session['id'] as String)
          .toList(growable: false);
      final venueId = snapshot.customers.isEmpty
          ? null
          : snapshot.customers.first['venue_id'] as String;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
      if (!_sameSessionIds(sessionIds, _sessionIds) || venueId != _venueId) {
        _sessionIds = sessionIds;
        _venueId = venueId;
        _subscribe();
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(error.message);
          _loading = false;
        });
      }
    } on CustomerFlowException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Chargement de l’espace client impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = 'Votre espace client n’a pas pu être chargé.';
          _loading = false;
        });
      }
    }
  }

  bool _sameSessionIds(List<String> first, List<String> second) =>
      first.length == second.length &&
      first.every((sessionId) => second.contains(sessionId));

  void _subscribeToUserNotifications() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _userChannel = Supabase.instance.client.channel(
      'user:$userId',
      opts: const RealtimeChannelConfig(private: true),
    )..onBroadcast(event: 'INSERT', callback: (_) => _scheduleRefresh());
    _userChannel!.subscribe((status, error) {
      if ((status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) &&
          mounted) {
        setState(
          () => _error =
              'La synchronisation des notifications est interrompue. Actualisez pour réessayer.',
        );
      }
    });
  }

  void _subscribe() {
    for (final channel in _sessionChannels) {
      channel.unsubscribe();
    }
    _sessionChannels.clear();
    _catalogChannel?.unsubscribe();
    _inventoryChannel?.unsubscribe();
    _programChannel?.unsubscribe();
    final client = Supabase.instance.client;
    for (final sessionId in _sessionIds) {
      final channel = client.channel(
        'session:$sessionId',
        opts: const RealtimeChannelConfig(private: true),
      );
      for (final event in ['INSERT', 'UPDATE']) {
        channel.onBroadcast(event: event, callback: (_) => _scheduleRefresh());
      }
      channel.subscribe((status, error) {
        if ((status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) &&
            mounted) {
          setState(
            () => _error =
                'La synchronisation de vos sessions est interrompue. Réessayez.',
          );
        }
      });
      _sessionChannels.add(channel);
    }
    final venueId = _venueId;
    if (venueId != null) {
      _catalogChannel = client.channel(
        'venue:$venueId:catalog',
        opts: const RealtimeChannelConfig(private: true),
      );
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        _catalogChannel!.onBroadcast(
          event: event,
          callback: (_) => _scheduleRefresh(),
        );
      }
      _catalogChannel!.subscribe();
      _inventoryChannel = client.channel(
        'venue:$venueId:inventory',
        opts: const RealtimeChannelConfig(private: true),
      );
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        _inventoryChannel!.onBroadcast(
          event: event,
          callback: (_) => _scheduleRefresh(),
        );
      }
      _inventoryChannel!.subscribe((status, error) {
        if ((status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) &&
            mounted) {
          setState(
            () => _error =
                'La synchronisation du stock est interrompue. Réessayez.',
          );
        }
      });
      _programChannel = client.channel(
        'venue:$venueId:programs',
        opts: const RealtimeChannelConfig(private: true),
      );
      for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
        _programChannel!.onBroadcast(
          event: event,
          callback: (_) => _scheduleRefresh(),
        );
      }
      _programChannel!.subscribe((status, error) {
        if ((status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) &&
            mounted) {
          setState(
            () => _error =
                'La synchronisation des adhésions et formules est interrompue.',
          );
        }
      });
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _request(String type, Map<String, dynamic> payload) async {
    final sessions = _snapshot?.sessions ?? const [];
    if (sessions.isEmpty || _working) return;
    final requestedSessionId = GoRouterState.of(
      context,
    ).uri.queryParameters['sessionId'];
    final preferredSessionId = requestedSessionId ?? _selectedSessionId;
    final session = selectCustomerSession(
      sessions: sessions.cast<Map<String, dynamic>>(),
      requestedSessionId: preferredSessionId,
    );
    final sessionId = session?['id'] as String?;
    if (sessionId == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.createSessionRequest(
        sessionId: sessionId,
        type: type,
        payload: payload,
      );
      await _load();
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Création de la demande client impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La demande n’a pas pu être envoyée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(String message) {
    final code = message.toUpperCase();
    if (code.contains('REQUEST_ALREADY_PENDING')) {
      return 'Une demande de ce type est déjà en attente.';
    }
    if (code.contains('SESSION_NOT_ACTIVE')) {
      return 'La session n’est plus active. Demandez à l’équipe de vous aider.';
    }
    if (code.contains('GAME_NOT_MATCH_BASED')) {
      return 'Les demandes de match ne sont pas disponibles pour ce jeu.';
    }
    if (code.contains('GAME_NOT_TIME_BASED')) {
      return 'Les demandes de temps ne sont pas disponibles pour ce jeu.';
    }
    if (code.contains('PRODUCT_NOT_FOUND')) {
      return 'Ce produit n’est plus disponible.';
    }
    if (code.contains('PRODUCT_NOT_AVAILABLE')) {
      return 'Ce produit n’est plus en vente.';
    }
    if (code.contains('PRODUCT_PRICE_CHANGED')) {
      return 'Le prix a changé. Actualisez le catalogue avant de commander.';
    }
    if (code.contains('PRE_SESSION_ORDER_ALREADY_ATTACHED')) {
      return 'Cette commande a déjà été associée à une session.';
    }
    if (code.contains('PRE_SESSION_ORDER_NOT_FOUND')) {
      return 'Cette commande payée ne peut plus être associée.';
    }
    if (code.contains('INSUFFICIENT_STOCK')) {
      return 'Le stock est insuffisant pour cette quantité.';
    }
    if (code.contains('INVALID_QUANTITY')) {
      return 'Choisissez une quantité valide.';
    }
    if (code.contains('INSUFFICIENT_LOYALTY_POINTS')) {
      return 'Vous n’avez pas assez de points pour cette récompense.';
    }
    if (code.contains('REWARD_OUT_OF_STOCK')) {
      return 'Cette récompense n’est plus disponible en stock.';
    }
    if (code.contains('REWARD_NOT_AVAILABLE')) {
      return 'Cette récompense n’est plus proposée.';
    }
    if (code.contains('INSUFFICIENT_PACKAGE_MINUTES')) {
      return 'Le forfait ne contient pas assez de minutes.';
    }
    if (code.contains('PACKAGE_EXPIRED')) {
      return 'Ce forfait a expiré et ne peut plus être utilisé.';
    }
    if (code.contains('PACKAGE_SESSION_MISMATCH')) {
      return 'Ce forfait n’est pas associé à cette session.';
    }
    if (code.contains('GAME_NOT_TIME_BASED')) {
      return 'Les minutes de forfait ne peuvent pas être utilisées sur ce jeu.';
    }
    if (code.contains('FORBIDDEN')) {
      return 'Accès refusé. Vérifiez votre compte ou demandez au gérant.';
    }
    if (code.contains('UNAUTHENTICATED')) {
      return 'Session expirée. Veuillez vous reconnecter.';
    }
    if (message.trim().isNotEmpty && !code.contains('SOCKETEXCEPTION')) {
      return message;
    }
    return 'La demande a échoué. Vérifiez votre connexion et réessayez.';
  }

  Future<void> _orderProduct(
    Map<String, dynamic> product, {
    required bool canAddToSession,
    required String? sessionId,
  }) async {
    final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
    if (stock < 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ce produit est en rupture de stock.')),
        );
      }
      return;
    }
    if (_working) return;
    final quantity = await showDialog<_ProductOrderSelection>(
      context: context,
      builder: (context) => _ProductOrderDialog(
        name: product['name'] as String? ?? 'Produit',
        price: (product['sale_price'] as num).toDouble(),
        stock: stock,
        canAddToSession: canAddToSession,
      ),
    );
    if (quantity == null || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (quantity.addToSession) {
        final targetSession = sessionId;
        if (targetSession == null) {
          throw const CustomerFlowException(
            'Aucune session active pour cette commande.',
          );
        }
        await _repository.addProductToSession(
          sessionId: targetSession,
          productId: product['id'] as String,
          quantity: quantity.quantity,
          expectedUnitPrice: (product['sale_price'] as num).toDouble(),
        );
      } else {
        await _repository.requestStandaloneProductOrder(
          productId: product['id'] as String,
          quantity: quantity.quantity,
          expectedUnitPrice: (product['sale_price'] as num).toDouble(),
          paymentMethod: quantity.paymentMethod,
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              quantity.addToSession
                  ? 'Produit ajouté à la facture de votre session.'
                  : 'Demande envoyée. Réglez la commande au comptoir.',
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Commande client impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le produit n’a pas pu être commandé.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showSnackCatalog() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final session = selectCustomerSession(
      sessions: snapshot.sessions.cast<Map<String, dynamic>>(),
      requestedSessionId: _selectedSessionId,
    );
    final venueId =
        session?['venue_id'] ??
        (snapshot.customers.isEmpty
            ? null
            : snapshot.customers.first['venue_id']);
    final products = snapshot.products
        .where((product) => product['venue_id'] == venueId)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF13132B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bar & Snacks',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Choisissez une boisson ou un snack à commander.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: products.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun produit disponible.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppSurface(
                              borderRadius: 16,
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_bar_rounded, color: AppColors.amber),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['name'] as String? ?? 'Produit',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          stock > 0 ? 'Stock : $stock' : 'Rupture de stock',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: stock > 0 ? AppColors.muted : AppColors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${((product['sale_price'] as num?) ?? 0).toStringAsFixed(0)} DA',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: stock < 1
                                            ? null
                                            : () {
                                                Navigator.pop(context);
                                                _orderProduct(
                                                  product,
                                                  canAddToSession: session?['status'] == 'active',
                                                  sessionId: session?['id'] as String?,
                                                );
                                              },
                                        child: const Text('Commander', style: TextStyle(fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _attachPreSessionOrder(
    Map<String, dynamic> request,
    Map<String, dynamic> session,
  ) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.attachPreSessionOrder(
        requestId: request['id'] as String,
        sessionId: session['id'] as String,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Commande payée associée à la session, sans nouveau débit.',
            ),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Association de la commande pré-session impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La commande n’a pas pu être associée.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _claimLoyaltyReward(
    Map<String, dynamic> customer,
    Map<String, dynamic> reward,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demander cette récompense ?'),
        content: Text(
          '${reward['name']} · ${reward['points_cost']} points. '
          'L’équipe confirmera la remise sur place.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Demander'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _repository.redeemLoyaltyReward(
        customerId: customer['id'] as String,
        rewardId: reward['id'] as String,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande envoyée. Les points sont réservés.'),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Demande de récompense impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'La demande de récompense a échoué.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final customer = snapshot == null || snapshot.customers.isEmpty
        ? null
        : snapshot.customers.first;
    final requestedSessionId = GoRouterState.of(
      context,
    ).uri.queryParameters['sessionId'];
    final sessions = snapshot?.sessions ?? const <Map<String, dynamic>>[];
    final session = selectCustomerSession(
      sessions: sessions,
      requestedSessionId: requestedSessionId,
      selectedSessionId: _selectedSessionId,
    );
    final venue = customer?['venues'] as Map<String, dynamic>?;
    final game = session?['games'] as Map<String, dynamic>?;
    final requestedType = game?['game_mode'] == 'match_based'
        ? 'match'
        : 'time';
    final hasPendingRequest =
        snapshot?.requests.any(
          (request) =>
              request['session_id'] == session?['id'] &&
              request['type'] == requestedType &&
              request['status'] == 'pending',
        ) ??
        false;

    return ResponsiveScaffold(
      currentIndex: 0,
      isStaff: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackground(),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 28),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
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
                              const SizedBox(width: 6),
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
                          const SizedBox(height: 2),
                          Text(
                            venue?['name'] as String? ?? 'Espace Client VIP',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          AppSurface(
                            borderRadius: 15,
                            padding: const EdgeInsets.all(10),
                            onTap: () => context.push('/notifications'),
                            child: const Icon(
                              Icons.notifications_none_rounded,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppSurface(
                            borderRadius: 15,
                            padding: const EdgeInsets.all(10),
                            onTap: () => context.push('/customer/profile'),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (customer != null) ...[
                    const SizedBox(height: 16),
                    _buildHeroBanner(customer, venue, snapshot),
                    const SizedBox(height: 20),
                    const Text(
                      'ACTIONS RAPIDES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.2,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CustomerQuickActionTile(
                            icon: Icons.sports_esports_rounded,
                            gradientColors: const [Color(0xFF3B82F6), Color(0xFF6366F1)],
                            title: 'Postes',
                            subtitle: 'Voir les أجهزة',
                            onTap: () => context.push('/posts'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CustomerQuickActionTile(
                            icon: Icons.disc_full_rounded,
                            gradientColors: const [AppColors.primary, Color(0xFFC026D3)],
                            title: 'Catalogue',
                            subtitle: 'Jeux et أسعار',
                            onTap: () => context.push('/games'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CustomerQuickActionTile(
                            icon: Icons.shopping_bag_rounded,
                            gradientColors: const [AppColors.amber, AppColors.red],
                            title: 'Bar & Snacks',
                            subtitle: 'Boissons et وجبات',
                            onTap: _showSnackCatalog,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CustomerQuickActionTile(
                            icon: Icons.calendar_month_rounded,
                            gradientColors: const [AppColors.green, Color(0xFF06B6D4)],
                            title: 'Réservations',
                            subtitle: 'Réserver جلسة',
                            onTap: () => context.push('/booking'),
                          ),
                        ),
                      ],
                    ),
                    if (snapshot != null && snapshot.games.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _CustomerGamesCarousel(games: snapshot.games),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _MessageCard(message: _error!, isError: true),
                  ],
                  if (_loading && snapshot == null)
                    const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot == null)
                    _MessageCard(
                      message:
                          _error ?? 'Votre espace client n’a pas pu être chargé.',
                      isError: true,
                    )
                  else if (customer == null)
                    _buildLinkPrompt()
                  else ...[
                    const SizedBox(height: 18),
                    _buildAccountBalances(snapshot),
                    if (snapshot.ledgerEntries.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildFinancialHistory(snapshot),
                    ],
                    const SizedBox(height: 14),
                    _buildLoyalty(snapshot, session),
                    const SizedBox(height: 18),
                    if (snapshot.sessions.length > 1)
                      _buildSessionSelector(snapshot.sessions, session),
                    if (snapshot.sessions.length > 1) const SizedBox(height: 12),
                    if (session == null)
                      _buildNoSession(snapshot)
                    else
                      _buildSession(session, snapshot, hasPendingRequest),
                    const SizedBox(height: 18),
                    _buildProducts(snapshot, session),
                    const SizedBox(height: 18),
                    _buildGames(snapshot),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroBanner(Map<String, dynamic>? customer, Map<String, dynamic>? venue, CustomerHomeSnapshot? snapshot) {
    final name = customer?['full_name'] as String? ?? 'Joueur';
    final venueName = venue?['name'] as String? ?? 'Ghost Gaming Lounge';

    double walletBalance = 0;
    if (snapshot != null && snapshot.balances.isNotEmpty) {
      walletBalance = (snapshot.balances.first['wallet_balance'] as num?)?.toDouble() ?? 0;
    }
    int loyaltyPoints = 0;
    if (snapshot != null && snapshot.loyaltyBalances.isNotEmpty) {
      loyaltyPoints = (snapshot.loyaltyBalances.first['points_balance'] as num?)?.toInt() ?? 0;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 178,
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
                    Colors.black.withValues(alpha: 0.92),
                    Colors.black.withValues(alpha: 0.70),
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xE6281845),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: const Color(0x8C8C5AE6)),
                    ),
                    child: const Text(
                      'PS4 & PS5 LOUNGE · PLAYER',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: Color(0xFFC0A8FF),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ready to play?',
                    style: TextStyle(
                      fontFamily: 'Orbitron',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Bienvenue, $name · $venueName',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_rounded, size: 13, color: AppColors.green),
                            const SizedBox(width: 5),
                            Text(
                              '${walletBalance.toStringAsFixed(0)} DA',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.pink.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.pink.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.stars_rounded, size: 13, color: AppColors.pink),
                            const SizedBox(width: 5),
                            Text(
                              '$loyaltyPoints pts',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSelector(
    List<Map<String, dynamic>> sessions,
    Map<String, dynamic>? selected,
  ) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final item in sessions)
        ChoiceChip(
          label: Text(
            (item['posts'] as Map<String, dynamic>?)?['name'] as String? ??
                'Session',
          ),
          selected: item['id'] == selected?['id'],
          onSelected: (isSelected) {
            if (isSelected) {
              setState(() => _selectedSessionId = item['id'] as String);
              context.go(
                '/customer/home?sessionId=${Uri.encodeQueryComponent(item['id'] as String)}',
              );
            }
          },
        ),
    ],
  );

  Widget _buildAccountBalances(CustomerHomeSnapshot snapshot) {
    final balancesByCustomer = {
      for (final row in snapshot.balances) row['customer_id'] as String: row,
    };
    final accounts = snapshot.customers
        .where((customer) => balancesByCustomer.containsKey(customer['id']))
        .toList(growable: false);
    if (accounts.isEmpty) return const SizedBox.shrink();
    return AppSurface(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mes comptes',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...accounts.map((account) {
            final balance = balancesByCustomer[account['id']]!;
            final venue = account['venues'] as Map<String, dynamic>?;
            final wallet = (balance['wallet_balance'] as num?)?.toDouble() ?? 0;
            final credit = (balance['credit_balance'] as num?)?.toDouble() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      venue?['name'] as String? ?? 'Votre salle',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'Portefeuille ${wallet.toStringAsFixed(2)} DA',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Crédit ${credit.toStringAsFixed(2)} DA',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.amber,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFinancialHistory(CustomerHomeSnapshot snapshot) {
    final venueByCustomer = {
      for (final customer in snapshot.customers)
        customer['id'] as String:
            (customer['venues'] as Map<String, dynamic>?)?['name'] as String? ??
            'Votre salle',
    };
    String label(String reason) => switch (reason) {
      'wallet_top_up' => 'Rechargement du portefeuille',
      'session_spend' => 'Paiement depuis le portefeuille',
      'debt_created' => 'Achat à crédit',
      'credit_repayment' => 'Remboursement du crédit',
      _ => 'Mouvement de compte',
    };
    return AppSurface(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Derniers mouvements',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          for (final entry in snapshot.ledgerEntries.take(5))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    (entry['delta'] as num).toDouble() < 0
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    size: 18,
                    color: (entry['delta'] as num).toDouble() < 0
                        ? AppColors.amber
                        : AppColors.green,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label(entry['reason'] as String? ?? ''),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          venueByCustomer[entry['customer_id']] ??
                              'Votre salle',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(entry['delta'] as num).toDouble() > 0 ? '+' : ''}'
                    '${(entry['delta'] as num).toDouble().toStringAsFixed(2)} DA',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoyalty(
    CustomerHomeSnapshot snapshot,
    Map<String, dynamic>? session,
  ) {
    final balances = {
      for (final row in snapshot.loyaltyBalances)
        row['customer_id'] as String: (row['points_balance'] as num).toInt(),
    };
    final redemptionsByCustomer = <String, List<Map<String, dynamic>>>{};
    for (final redemption in snapshot.loyaltyRedemptions) {
      redemptionsByCustomer
          .putIfAbsent(redemption['customer_id'] as String, () => [])
          .add(redemption);
    }

    Widget buildPrograms(
      CustomerHomeSnapshot snapshot,
      Map<String, dynamic>? session,
    ) {
      final now = DateTime.now();
      final linkedCustomerIds = snapshot.customers
          .map((customer) => customer['id'] as String)
          .toSet();
      final memberships = snapshot.memberships.where((membership) {
        final timeZone =
            snapshot.timeZonesByVenue[membership['venue_id'] as String? ??
                ''] ??
            'Africa/Algiers';
        final starts = VenueTimeZone.parse(
          membership['starts_at'] as String?,
          timeZone,
        );
        final ends = VenueTimeZone.parse(
          membership['ends_at'] as String?,
          timeZone,
        );
        return linkedCustomerIds.contains(membership['customer_id']) &&
            starts != null &&
            ends != null &&
            !starts.isAfter(now) &&
            ends.isAfter(now);
      }).toList();
      final purchases = snapshot.packagePurchases
          .where(
            (purchase) => linkedCustomerIds.contains(purchase['customer_id']),
          )
          .toList();
      final customerVenueIds = snapshot.customers
          .map((customer) => customer['venue_id'] as String)
          .toSet();
      final plans = snapshot.membershipPlans
          .where((plan) => customerVenueIds.contains(plan['venue_id']))
          .toList();
      final packages = snapshot.packages
          .where((package) => customerVenueIds.contains(package['venue_id']))
          .toList();
      if (memberships.isEmpty &&
          purchases.isEmpty &&
          plans.isEmpty &&
          packages.isEmpty) {
        return const SizedBox.shrink();
      }
      final canUseMinutes =
          session != null &&
          session['status'] == 'active' &&
          (session['games'] as Map<String, dynamic>?)?['game_mode'] !=
              'match_based';
      Future<void> redeemPackageMinutes(
        Map<String, dynamic> purchase,
        Map<String, dynamic> activeSession,
      ) async {
        if (_working) return;
        var minutes = 30;
        final selected = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Utiliser le forfait'),
            content: TextFormField(
              initialValue: '30',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Minutes à ajouter',
                helperText:
                    'Disponible : ${purchase['gaming_minutes_remaining']} min',
              ),
              onChanged: (value) => minutes = int.tryParse(value) ?? 0,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, minutes),
                child: const Text('Utiliser'),
              ),
            ],
          ),
        );
        if (selected == null || selected < 1 || !mounted) return;
        setState(() {
          _working = true;
          _error = null;
        });
        try {
          await _repository.redeemPackageMinutes(
            purchaseId: purchase['id'] as String,
            sessionId: activeSession['id'] as String,
            minutes: selected,
          );
          await _load();
        } on PostgrestException catch (error) {
          if (mounted) setState(() => _error = _friendlyError(error.message));
        } catch (error, stackTrace) {
          debugPrint('Utilisation du forfait impossible : $error');
          debugPrintStack(stackTrace: stackTrace);
          if (mounted) {
            setState(() => _error = 'Le forfait n’a pas pu être utilisé.');
          }
        } finally {
          if (mounted) setState(() => _working = false);
        }
      }

      return AppSurface(
        borderRadius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adhésions & formules',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            for (final membership in memberships)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adhésion · ${membership['plan_name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if ((membership['benefits'] as String? ?? '').isNotEmpty)
                      Text(
                        membership['benefits'] as String,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            for (final purchase in purchases)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${purchase['package_name']} · '
                      '${_packageIsExpired(purchase) ? 'forfait expiré' : '${purchase['gaming_minutes_remaining']} min restantes'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (!_packageIsExpired(purchase) &&
                        canUseMinutes &&
                        (purchase['gaming_minutes_remaining'] as num).toInt() >
                            0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _working
                              ? null
                              : () => redeemPackageMinutes(purchase, session),
                          child: const Text('Ajouter des minutes'),
                        ),
                      ),
                    for (final item
                        in (purchase['package_purchase_items'] as List? ??
                                const [])
                            .cast<Map<String, dynamic>>())
                      if (!_packageIsExpired(purchase) &&
                          (item['remaining_quantity'] as num).toInt() > 0)
                        Text(
                          '${item['product_name']} · '
                          '${item['remaining_quantity']} à retirer auprès de l’équipe',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                  ],
                ),
              ),
            if (plans.isNotEmpty || packages.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Offres disponibles · demandez à l’équipe',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              for (final plan in plans)
                Text(
                  '• ${plan['name']} · ${plan['duration_days']} jours'
                  '${(plan['benefits'] as String? ?? '').isEmpty ? '' : ' · ${plan['benefits']}'}',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
              for (final package in packages) ...[
                Text(
                  '• ${package['name']} · ${package['gaming_minutes']} min · '
                  '${(package['price'] as num).toStringAsFixed(2)} DA',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                ),
                for (final item
                    in (package['package_items'] as List? ?? const [])
                        .cast<Map<String, dynamic>>())
                  Text(
                    '   ${item['quantity']} × '
                    '${(item['products'] as Map<String, dynamic>?)?['name'] ?? 'Produit'}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        if (snapshot.loyaltyBalances.isNotEmpty)
          AppSurface(
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Programme de fidélité',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                for (final customer in snapshot.customers)
                  if (balances.containsKey(customer['id']))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (customer['venues']
                                              as Map<String, dynamic>?)?['name']
                                          as String? ??
                                      'Votre salle',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${balances[customer['id']]} points',
                                style: const TextStyle(
                                  color: AppColors.pink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          for (final reward in snapshot.loyaltyRewards.where(
                            (item) => item['venue_id'] == customer['venue_id'],
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                reward['name'] as String,
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Text(
                                '${reward['points_cost']} points'
                                '${reward['stock_quantity'] == null ? '' : ' · Stock ${reward['stock_quantity']}'}',
                                style: const TextStyle(fontSize: 10),
                              ),
                              trailing: TextButton(
                                onPressed:
                                    _working ||
                                        (balances[customer['id']] ?? 0) <
                                            (reward['points_cost'] as num)
                                                .toInt() ||
                                        ((reward['stock_quantity'] as num?)
                                                ?.toInt() ==
                                            0)
                                    ? null
                                    : () =>
                                          _claimLoyaltyReward(customer, reward),
                                child: const Text('Demander'),
                              ),
                            ),
                          for (final redemption
                              in (redemptionsByCustomer[customer['id']] ?? [])
                                  .take(2))
                            Text(
                              '${(redemption['loyalty_rewards'] as Map<String, dynamic>?)?['name'] ?? 'Récompense'} · '
                              '${switch (redemption['status']) {
                                'pending' => 'en attente',
                                'fulfilled' => 'remise effectuée',
                                'rejected' => 'refusée — points recrédités',
                                _ => 'mise à jour',
                              }}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        buildPrograms(snapshot, session),
      ],
    );
  }

  bool _packageIsExpired(Map<String, dynamic> purchase) {
    final venueId = purchase['venue_id'] as String?;
    final timeZone =
        _snapshot?.timeZonesByVenue[venueId ?? ''] ?? 'Africa/Algiers';
    final expiresAt = VenueTimeZone.parse(
      purchase['expires_at'] as String?,
      timeZone,
    );
    return expiresAt == null || !expiresAt.isAfter(VenueTimeZone.now(timeZone));
  }

  Widget _buildLinkPrompt() => Padding(
    padding: const EdgeInsets.only(top: 26),
    child: AppSurface(
      borderRadius: 24,
      child: Column(
        children: [
          const Icon(
            Icons.qr_code_scanner_rounded,
            size: 42,
            color: AppColors.pink,
          ),
          const SizedBox(height: 14),
          const Text(
            'Liez votre compte à une salle',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scannez le QR affiché sur un poste pour accéder au catalogue et à votre session.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'Lier un poste',
            onPressed: () => context.go('/customer/scan'),
          ),
        ],
      ),
    ),
  );

  Widget _buildNoSession(CustomerHomeSnapshot snapshot) => AppSurface(
    isSelected: true,
    borderRadius: 24,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.sports_esports_rounded,
          size: 28,
          color: AppColors.pink,
        ),
        const SizedBox(height: 12),
        const Text(
          'Aucune session en cours',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          'Demandez à un membre de l’équipe de démarrer votre session.',
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        if (snapshot.customers.length > 1) ...[
          const SizedBox(height: 12),
          const Text(
            'Vos salles sont synchronisées dans cet espace.',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ],
    ),
  );

  Widget _buildSession(
    Map<String, dynamic> session,
    CustomerHomeSnapshot snapshot,
    bool hasPendingRequest,
  ) {
    final game = session['games'] as Map<String, dynamic>?;
    final post = session['posts'] as Map<String, dynamic>?;
    final imageUrl = game?['image_url'] as String?;
    final bill = snapshot.bills.where(
      (row) => row['session_id'] == session['id'],
    );
    final balance = bill.isEmpty
        ? 0.0
        : (bill.first['balance_due'] as num?)?.toDouble() ?? 0;
    final gameMode = game?['game_mode'] as String? ?? 'time_based';
    final status = session['status'] as String? ?? 'active';

    return AppSurface(
      isSelected: true,
      borderRadius: 24,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          height: 230,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.surface1,
                    ),
                  ),
                )
              else
                const ColoredBox(color: AppColors.surface1),

              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.sports_esports_rounded,
                          color: AppColors.pink,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            post?['name'] as String? ?? 'Votre poste',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        _SessionStatus(status: status),
                      ],
                    ),

                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.black.withValues(alpha: 0.75),
                          border: Border.all(
                            color: AppColors.primaryLight.withValues(
                              alpha: 0.6,
                            ),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: gameMode == 'match_based'
                            ? Text(
                                'Matchs joués : ${session['match_count'] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryLight,
                                ),
                              )
                            : _CustomerSessionCountdown(
                                session: session,
                                timeZone:
                                    snapshot.timeZonesByVenue[session['venue_id']
                                            as String? ??
                                        ''] ??
                                    'Africa/Algiers',
                              ),
                      ),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          game?['name'] as String? ?? 'Jeu',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          'Solde : ${balance.toStringAsFixed(0)} DA',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.pink,
                          ),
                        ),
                      ],
                    ),

                    if (status == 'active' && !hasPendingRequest) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: gameMode == 'match_based'
                            ? AppButton(
                                label: _working
                                    ? 'Envoi…'
                                    : 'Demander +1 match',
                                onPressed: _working
                                    ? () {}
                                    : () => _request('match', {'qty': 1}),
                              )
                            : AppButton(
                                label: _working
                                    ? 'Envoi…'
                                    : 'Demander +10 minutes',
                                onPressed: _working
                                    ? () {}
                                    : () => _request('time', {'minutes': 10}),
                              ),
                      ),
                    ] else if (hasPendingRequest) ...[
                      const _MessageCard(
                        message: 'Votre demande est en attente de validation.',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGames(CustomerHomeSnapshot snapshot) {
    final venueId = snapshot.customers.isEmpty
        ? null
        : snapshot.customers.first['venue_id'];
    final games = snapshot.games
        .where((game) => game['venue_id'] == venueId)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Jeux disponibles',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (games.isEmpty)
          const _MessageCard(message: 'Aucun jeu disponible pour le moment.')
        else
          for (final game in games)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: AppSurface(
                borderRadius: 18,
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sports_esports_rounded,
                      color: AppColors.primaryLight,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            game['name'] as String? ?? 'Jeu',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            game['game_mode'] == 'match_based'
                                ? 'Tarif par match'
                                : 'Tarif selon la durée',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${((game['price'] as num?) ?? 0).toStringAsFixed(0)} DA',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildProducts(
    CustomerHomeSnapshot snapshot,
    Map<String, dynamic>? session,
  ) {
    final venueId =
        session?['venue_id'] ??
        (snapshot.customers.isEmpty
            ? null
            : snapshot.customers.first['venue_id']);
    final products = snapshot.products
        .where((product) => product['venue_id'] == venueId)
        .toList();
    final standaloneRequests = snapshot.standaloneOrderRequests
        .where((request) => request['venue_id'] == venueId)
        .take(5)
        .toList();
    final sessionId = session?['id'] as String?;
    final canOrder = session?['status'] == 'active';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Produits',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ajoutez un produit à votre session ou commandez sans session et payez au comptoir.',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 10),
        if (products.isEmpty)
          const _MessageCard(
            message: 'Aucun produit disponible pour le moment.',
          )
        else
          for (final product in products)
            Builder(
              builder: (context) {
                final stock = (product['stock_quantity'] as num?)?.toInt() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: AppSurface(
                    borderRadius: 18,
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_cafe_rounded,
                          color: AppColors.amber,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['name'] as String? ?? 'Produit',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                stock > 0
                                    ? 'Stock disponible : $stock'
                                    : 'Rupture de stock',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${((product['sale_price'] as num?) ?? 0).toStringAsFixed(0)} DA',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextButton(
                              onPressed: stock > 0 && !_working
                                  ? () => _orderProduct(
                                      product,
                                      canAddToSession:
                                          canOrder && sessionId != null,
                                      sessionId: sessionId,
                                    )
                                  : null,
                              child: const Text(
                                'Commander',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        if (standaloneRequests.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Commandes au comptoir',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...standaloneRequests.map((request) {
            final product = request['products'];
            final productName = product is Map<String, dynamic>
                ? product['name'] as String? ?? 'Produit'
                : 'Produit';
            final order = request['orders'];
            final orderSessionId = order is Map<String, dynamic>
                ? order['session_id'] as String?
                : null;
            final isAttached = orderSessionId != null;
            final status = switch (request['status']) {
              'pending' => 'En attente de paiement au comptoir',
              'completed' =>
                isAttached ? 'Payée · associée à une session' : 'Payée',
              'rejected' => 'Refusée par l’équipe',
              _ => 'Statut inconnu',
            };
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppSurface(
                borderRadius: 16,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$productName × ${request['quantity']} · $status',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    if (session != null &&
                        canAttachPreSessionOrder(
                          requestStatus: request['status'] as String? ?? '',
                          orderSessionId: orderSessionId,
                          sessionStatus: session['status'] as String?,
                        )) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _working
                            ? null
                            : () => _attachPreSessionOrder(request, session),
                        icon: const Icon(Icons.link_rounded, size: 16),
                        label: const Text(
                          'Associer à cette session (déjà payée)',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _ProductOrderDialog extends StatefulWidget {
  const _ProductOrderDialog({
    required this.name,
    required this.price,
    required this.stock,
    required this.canAddToSession,
  });

  final String name;
  final double price;
  final int stock;
  final bool canAddToSession;

  @override
  State<_ProductOrderDialog> createState() => _ProductOrderDialogState();
}

class _ProductOrderDialogState extends State<_ProductOrderDialog> {
  int _quantity = 1;
  String _paymentMethod = 'cash';

  @override
  Widget build(BuildContext context) {
    final maximum = widget.stock.clamp(1, 100);
    const paymentMethods = [
      {'id': 'cash', 'label': 'Espèces (نقداً)', 'icon': Icons.payments_rounded},
      {'id': 'credit', 'label': 'Crédit / Sur facture (على الأجل)', 'icon': Icons.receipt_long_rounded},
    ];

    return AlertDialog(
      title: const Text('Commander un produit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              '${widget.price.toStringAsFixed(0)} DA · Stock : ${widget.stock}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Diminuer la quantité',
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Augmenter la quantité',
                  onPressed: _quantity < maximum
                      ? () => setState(() => _quantity++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Total : ${(widget.price * _quantity).toStringAsFixed(0)} DA',
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 16),
            const Text(
              'Mode de paiement (طريقة الدفع)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: paymentMethods.map((m) => DropdownMenuItem(
                value: m['id'] as String,
                child: Row(
                  children: [
                    Icon(m['icon'] as IconData, size: 16, color: AppColors.primaryLight),
                    const SizedBox(width: 8),
                    Text(m['label'] as String, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _paymentMethod = val);
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
        if (widget.canAddToSession)
          FilledButton.tonal(
            onPressed: () => Navigator.pop(
              context,
              _ProductOrderSelection(quantity: _quantity, addToSession: true, paymentMethod: _paymentMethod),
            ),
            child: const Text('Ajouter à la session'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ProductOrderSelection(quantity: _quantity, addToSession: false, paymentMethod: _paymentMethod),
          ),
          child: const Text('Commander'),
        ),
      ],
    );
  }
}

class _ProductOrderSelection {
  const _ProductOrderSelection({
    required this.quantity,
    required this.addToSession,
    required this.paymentMethod,
  });

  final int quantity;
  final bool addToSession;
  final String paymentMethod;
}

class _SessionMetric extends StatelessWidget {
  const _SessionMetric({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF111126),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.muted),
          ),
          const SizedBox(height: 4),
          child ??
              Text(
                value ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
        ],
      ),
    ),
  );
}

class _CustomerSessionCountdown extends StatefulWidget {
  const _CustomerSessionCountdown({
    required this.session,
    required this.timeZone,
  });

  final Map<String, dynamic> session;
  final String timeZone;

  @override
  State<_CustomerSessionCountdown> createState() =>
      _CustomerSessionCountdownState();
}

class _CustomerSessionCountdownState extends State<_CustomerSessionCountdown>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _CustomerSessionCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session['status'] != widget.session['status']) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.session['status'] == 'active' &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
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

  String _remaining() {
    final session = widget.session;
    final planned = (session['planned_duration_seconds'] as num?)?.toInt() ?? 0;
    final started = VenueTimeZone.parse(
      session['started_at'] as String?,
      widget.timeZone,
    );
    if (started == null) return '—';
    final paused = VenueTimeZone.parse(
      session['paused_at'] as String?,
      widget.timeZone,
    );
    final ended = VenueTimeZone.parse(
      session['ended_at'] as String?,
      widget.timeZone,
    );
    final stopAt = session['status'] == 'paused' && paused != null
        ? paused
        : ended ?? DateTime.now();
    final elapsed =
        stopAt.difference(started).inSeconds -
        ((session['total_paused_seconds'] as num?)?.toInt() ?? 0);
    final seconds = (planned - elapsed).clamp(0, planned);
    return '${seconds ~/ 3600}h ${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}m';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    _remaining(),
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  );
}

class _SessionStatus extends StatelessWidget {
  const _SessionStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final paused = status == 'paused';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: (paused ? AppColors.amber : AppColors.green).withValues(
          alpha: 0.15,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        paused ? 'En pause' : 'En cours',
        style: TextStyle(
          fontSize: 10,
          color: paused ? AppColors.amber : AppColors.green,
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    child: Text(
      message,
      style: TextStyle(
        fontSize: 12,
        height: 1.4,
        color: isError ? AppColors.red : AppColors.muted,
      ),
    ),
  );
}

class _CustomerQuickActionTile extends StatelessWidget {
  const _CustomerQuickActionTile({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 10, color: AppColors.muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerGamesCarousel extends StatefulWidget {
  const _CustomerGamesCarousel({required this.games});

  final List<Map<String, dynamic>> games;

  @override
  State<_CustomerGamesCarousel> createState() => _CustomerGamesCarouselState();
}

class _CustomerGamesCarouselState extends State<_CustomerGamesCarousel>
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
  void didUpdateWidget(covariant _CustomerGamesCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.games.length != oldWidget.games.length &&
        _page >= widget.games.length) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
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
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'JEUX EN VEDETTE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.2,
                color: AppColors.muted,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/games'),
              child: const Text(
                'Voir tout >',
                style: TextStyle(fontSize: 12, color: AppColors.pink, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                final name = game['name'] as String? ?? 'Jeu';
                final platform = game['platform'] as String? ?? 'PS5';
                final category = game['category'] as String? ?? 'Gaming';
                final price = (game['price'] as num?)?.toDouble() ?? 0;
                final imageUrl = game['image_url'] as String?;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () => context.push('/games'),
                    borderRadius: BorderRadius.circular(27),
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
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.55),
                                      Colors.black.withValues(alpha: 0.92),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xE6130B24),
                                          borderRadius: BorderRadius.circular(99),
                                          border: Border.all(color: const Color(0x668E51FF)),
                                        ),
                                        child: Text(
                                          platform,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFD6C2FF),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.pink.withValues(alpha: 0.25),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: AppColors.pink.withValues(alpha: 0.5)),
                                        ),
                                        child: Text(
                                          '${price.toStringAsFixed(0)} DA',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        category.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.5,
                                          color: AppColors.pink,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.games.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.games.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: active ? AppColors.pink : Colors.white24,
                  boxShadow: active
                      ? const [BoxShadow(color: AppColors.pink, blurRadius: 8)]
                      : null,
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}
