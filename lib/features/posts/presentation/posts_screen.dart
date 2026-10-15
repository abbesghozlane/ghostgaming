import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_bottom_nav.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../app/widgets/responsive_scaffold.dart';
import '../../../core/data/current_role_cache.dart';
import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';
import 'package:intl/intl.dart';
import '../../sessions/data/session_dashboard_repository.dart';
import '../../sessions/domain/session_dashboard_models.dart';
import '../../sessions/presentation/session_dashboard_view_model.dart';
import '../../customers/data/customer_repository.dart';
import 'interactive_post_card_media.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  final _client = Supabase.instance.client;
  late final SessionDashboardViewModel _viewModel;
  VenueContext? _venue;
  bool _working = false;
  String? _error;
  String _searchQuery = '';
  String _filterStatus = 'all'; // 'all', 'available', 'active', 'paused', 'waiting_payment', 'maintenance'
  bool _isCarouselView = true;
  final PageController _carouselController = PageController(viewportFraction: 0.96);
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewModel = SessionDashboardViewModel(
      SessionDashboardRepository(_client),
    )..initialize();
    _loadVenue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel.refresh();
    _loadVenue();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _carouselController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  String? _currentCustomerId;

  Future<void> _loadVenue() async {
    try {
      final venue = await VenueRepository(_client).currentVenue();
      if (mounted) setState(() => _venue = venue);
      final user = _client.auth.currentUser;
      if (user != null) {
        final cust = await _client
            .from('customers')
            .select('id')
            .eq('user_id', user.id)
            .maybeSingle();
        if (cust != null && mounted) {
          setState(() => _currentCustomerId = cust['id'] as String?);
        }
      }
    } catch (_) {}
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

    if (initialPost != null) {
      final existingSession = _sessionForPost(snapshot.sessions, initialPost.id);
      if (existingSession != null) {
        _showMessage('Ce poste a déjà une session active.');
        return;
      }
      final compatibleGames = snapshot.games
          .where((game) => initialPost.supportsGame(game.id))
          .toList();
      if (compatibleGames.isEmpty) {
        _showMessage('Aucun jeu compatible avec ce poste.');
        return;
      }

      final result = await showDialog<_StartSessionSelection>(
        context: context,
        builder: (context) => _StartSessionDialog(
          initialPost: initialPost,
          posts: [initialPost],
          games: snapshot.games,
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
      if (!mounted) return;
      if (_viewModel.errorMessage != null) {
        _showMessage(_viewModel.errorMessage!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session démarrée avec succès sur ${result.post.name} !'),
            backgroundColor: AppColors.green,
          ),
        );
      }
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
        posts: availablePosts,
        games: snapshot.games,
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
    if (!mounted) return;
    if (_viewModel.errorMessage != null) {
      _showMessage(_viewModel.errorMessage!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session démarrée avec succès sur ${result.post.name} !'),
          backgroundColor: AppColors.green,
        ),
      );
    }
  }

  String _formatRequestError(dynamic error) => _formatRequestErrorHelper(error);

  Future<void> _sessionAction(
    ActiveGamingSession session,
    String action,
  ) async {
    final isCust = _venue?.role == 'customer';

    if (action == 'customer_request_product' || (isCust && action == 'add_product')) {
      await _addProductToSession(session);
      return;
    }
    
    if (action == 'customer_request_time' || (isCust && action == 'add_time')) {
      if (session.game?.mode == 'match_based') {
        final qty = await _askForMatchQtyAndDuration();
        if (qty == null) return;
        try {
          await CustomerRepository(_client).createSessionRequest(
            sessionId: session.id,
            type: 'match',
            payload: {'qty': qty},
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Demande de match envoyée au gérant !'),
                backgroundColor: AppColors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) _showMessage(_formatRequestError(e));
        }
        return;
      }

      final minutes = await _askForMinutes(session);
      if (minutes == null) return;
      try {
        await CustomerRepository(_client).createSessionRequest(
          sessionId: session.id,
          type: 'time',
          payload: {'minutes': minutes},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demande de prolongation envoyée au gérant !'),
              backgroundColor: AppColors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) _showMessage(_formatRequestError(e));
      }
      return;
    }

    if (isCust && action == 'add_match') {
      final qty = await _askForMatchQtyAndDuration();
      if (qty == null) return;
      try {
        await CustomerRepository(_client).createSessionRequest(
          sessionId: session.id,
          type: 'match',
          payload: {'qty': qty},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demande de match envoyée au gérant !'),
              backgroundColor: AppColors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) _showMessage(_formatRequestError(e));
      }
      return;
    }

    if (action == 'customer_request_pause' || (isCust && (action == 'pause_session' || action == 'resume_session'))) {
      try {
        await CustomerRepository(_client).createSessionRequest(
          sessionId: session.id,
          type: 'time',
          payload: {'pause_requested': true},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demande de pause envoyée au gérant !'),
              backgroundColor: AppColors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) _showMessage(_formatRequestError(e));
      }
      return;
    }

    if (action == 'customer_request_end' || (isCust && action == 'end_session')) {
      try {
        await CustomerRepository(_client).createSessionRequest(
          sessionId: session.id,
          type: 'checkout',
          payload: {},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demande de fin de session envoyée au gérant !'),
              backgroundColor: AppColors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) _showMessage('Impossible d’envoyer la demande : $e');
      }
      return;
    }

    if (isCust) {
      _showMessage('Action réservée au gérant de la salle.');
      return;
    }

    if (action == 'end_session' || action == 'pay_session') {
      await _endAndPaySession(session);
      return;
    }

    int? minutes;
    int? qty;
    if (action == 'add_time') {
      minutes = await _askForMinutes(session);
      if (minutes == null) return;
    }
    if (action == 'add_match') {
      qty = await _askForMatchQtyAndDuration();
      if (qty == null) return;
    }
    await _viewModel.runSessionAction(session, action, quantity: qty, minutes: minutes);
  }

  Future<int?> _askForMinutes(ActiveGamingSession session) async {
    final game = session.game;
    final tiers = game?.pricingTiers ?? const {};
    final defaultMins = [15, 30, 60, 90, 120, 180];
    final tierMins = tiers.keys
        .map((k) => int.tryParse(k) ?? 0)
        .where((m) => m > 0);
    final availableMins = {...defaultMins, ...tierMins}.toList()..sort();

    int selectedMinutes =
        availableMins.contains(30) ? 30 : availableMins.first;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) {
          final tierPrice = tiers[selectedMinutes.toString()];
          return AlertDialog(
            title: Text('Ajouter du temps · ${session.postName ?? 'Poste'}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choisissez le forfait de temps pour ${game?.name ?? 'le jeu'} :',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableMins.map((mins) {
                    final isSelected = selectedMinutes == mins;
                    final price = tiers[mins.toString()];
                    final timeLabel = mins >= 60
                        ? '${mins ~/ 60}h${mins % 60 > 0 ? '${mins % 60}' : ''}'
                        : '$mins min';
                    final displayLabel = price != null
                        ? '$timeLabel (${price.toStringAsFixed(0)} DA)'
                        : timeLabel;

                    return ChoiceChip(
                      label: Text(displayLabel),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface2,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.muted,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                      onSelected: (_) =>
                          setStateModal(() => selectedMinutes = mins),
                    );
                  }).toList(),
                ),
                if (tierPrice != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryLight.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sell_outlined,
                          size: 16,
                          color: AppColors.primaryLight,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Prix du forfait : ${tierPrice.toStringAsFixed(0)} DA',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selectedMinutes),
                child: const Text('Ajouter au poste'),
              ),
            ],
          );
        },
      ),
    );
    return result;
  }

  Future<int?> _askForMatchQtyAndDuration() async {
    int matchDuration = 10;
    int qty = 1;
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          title: const Text('Ajouter un match (FIFA / eFootball)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Durée du match dans le jeu :', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [6, 8, 10, 16].map((d) {
                  return ChoiceChip(
                    label: Text('$d min'),
                    selected: matchDuration == d,
                    onSelected: (_) => setStateModal(() => matchDuration = d),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Nombre de matchs :', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () => setStateModal(() => qty = qty > 1 ? qty - 1 : 1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  IconButton(
                    onPressed: () => setStateModal(() => qty++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {'qty': qty, 'duration': matchDuration}),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return null;
    return result['qty'];
  }

  Future<void> _transferSession(ActiveGamingSession session) async {
    final snapshot = _viewModel.snapshot;
    if (snapshot == null) return;
    final targets = transferablePosts(snapshot.posts, session);
    if (targets.isEmpty) {
      _showMessage('Aucun poste disponible ou compatible pour le transfert.');
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

  Future<void> _requestPostReservation(GamingPost post) async {
    final snapshot = _viewModel.snapshot;
    if (snapshot == null) return;
    final timeZone = _venue?.timeZone ?? 'Africa/Algiers';
    final customerRepo = CustomerRepository(_client);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _CustomerStartSessionDialog(
        initialPost: post,
        posts: snapshot.posts,
        games: snapshot.games,
        timeZone: timeZone,
        onRequest: (p, game, durationMinutes) async {
          await customerRepo.enqueuePostRequest(
            postId: p.id,
            gameId: game.id,
            requestedMinutes: durationMinutes,
          );
        },
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Votre demande de session a été envoyée au gérant. Vous recevrez une notification dès sa validation.',
          ),
          backgroundColor: AppColors.green,
        ),
      );
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

    if (_venue?.role == 'customer') {
      try {
        await CustomerRepository(_client).createSessionRequest(
          sessionId: session.id,
          type: 'product',
          payload: {
            'product_id': result.product.id,
            'product_name': result.product.name,
            'quantity': result.quantity,
            'unit_price': result.product.price,
          },
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Demande de snack/produit envoyée au gérant !'),
              backgroundColor: AppColors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) _showMessage('Erreur commande : $e');
      }
      return;
    }

    await _viewModel.addProductToSession(
      session,
      result.product,
      result.quantity,
    );
  }

  Future<void> _endAndPaySession(ActiveGamingSession session) async {
    List<Map<String, dynamic>> orderItems = [];
    try {
      orderItems = await _viewModel.loadSessionOrderItems(session.id);
    } catch (_) {}

    if (!mounted) return;
    final lines = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (context) => _SessionPaymentDialog(
        session: session,
        orderItems: orderItems,
        canManageCredit: _viewModel.snapshot?.canManageCredit ?? false,
      ),
    );
    if (lines == null) return;

    if (session.status == 'active' || session.status == 'paused') {
      await _viewModel.runSessionAction(session, 'end_session');
    }
    await _viewModel.paySession(session, lines);
  }

  Future<void> _applyPromotion(ActiveGamingSession session) async {
    final promotions = _viewModel.snapshot?.promotions ?? [];
    if (promotions.isEmpty) {
      _showMessage('Aucune promotion active pour cette salle.');
      return;
    }
    final promotion = await showDialog<SessionPromotion>(
      context: context,
      builder: (context) => _SessionPromotionDialog(promotions: promotions),
    );
    if (promotion == null) return;
    await _viewModel.applyPromotion(session, promotion);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editPost([GamingPost? post]) async {
    final venue = _venue;
    if (venue == null || !venue.canManageCatalog) return;
    List<Map<String, dynamic>> games;
    Set<String> supportedGameIds;
    Map<String, double> priceOverrides = {};
    try {
      games =
          (await _client
                  .from('games')
                  .select('id, name, price, pricing_unit, is_available')
                  .eq('venue_id', venue.id)
                  .order('name'))
              .cast<Map<String, dynamic>>();
      if (post == null) {
        supportedGameIds = games.map((game) => game['id'] as String).toSet();
      } else {
        final links = await _client
            .from('post_games')
            .select('game_id')
            .eq('post_id', post.id);
        final linkedIds = links
            .map((link) => link['game_id'] as String)
            .toSet();
        supportedGameIds = linkedIds.isEmpty
            ? games.map((game) => game['id'] as String).toSet()
            : linkedIds;
        final overrides = await _client
            .from('post_game_prices')
            .select('game_id, price_override')
            .eq('post_id', post.id);
        priceOverrides = {
          for (final row in overrides)
            row['game_id'] as String: (row['price_override'] as num).toDouble(),
        };
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
      return;
    } catch (error, stackTrace) {
      debugPrint('Chargement des jeux compatibles impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _error = 'Les jeux compatibles n’ont pas pu être chargés.',
        );
      }
      return;
    }
    if (!mounted) return;
    final result = await showDialog<_PostFormValue>(
      context: context,
      builder: (context) => _PostFormDialog(
        nextNumber:
            (_viewModel.snapshot?.posts ?? []).fold<int>(
              0,
              (current, item) => item.number > current ? item.number : current,
            ) +
            1,
        existing: post,
        games: games,
        supportedGameIds: supportedGameIds,
        priceOverrides: priceOverrides,
      ),
    );
    if (!mounted || result == null) return;
    if (games.isNotEmpty && result.supportedGameIds.isEmpty) {
      setState(
        () => _error = 'Sélectionnez au moins un jeu compatible avec ce poste.',
      );
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await executeIdempotentRpc<void>(_client, 'save_post_configuration', {
        'p_op': OperationId.create(),
        'p_venue': venue.id,
        'p_post': post?.id,
        'p_number': post == null ? _nextAvailableNumber() : null,
        'p_name': result.name,
        'p_device': result.device,
        'p_max_players': result.maxPlayers,
        'p_zone': result.zone.isEmpty ? null : result.zone,
        'p_game_ids': result.supportedGameIds.length == games.length
            ? <String>[]
            : result.supportedGameIds.toList(),
        'p_price_overrides': result.priceOverrides,
      });
      await _viewModel.refresh();
    } on PendingOfflineOperationException {
      if (mounted) {
        setState(
          () => _error =
              'La modification est enregistrée sur cet appareil et sera synchronisée au retour de la connexion.',
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Enregistrement du poste impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Le poste n’a pas pu être enregistré.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  int _nextAvailableNumber() {
    final used = (_viewModel.snapshot?.posts ?? []).map((post) => post.number).toSet();
    var next = 1;
    while (used.contains(next)) {
      next++;
    }
    return next;
  }

  Future<void> _setStatus(GamingPost post, String status) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await _client
          .from('posts')
          .update({'status': status})
          .eq('id', post.id);
      await _viewModel.refresh();
    } on PostgrestException catch (error) {
      setState(() => _error = _friendlyError(error.message));
    } catch (error, stackTrace) {
      debugPrint('Modification du statut du poste impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
      setState(() => _error = 'Le statut du poste n’a pas pu être modifié.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(String message) {
    final code = message.split(':').first.trim();
    return switch (code) {
      'FORBIDDEN' ||
      '42501' => 'Votre rôle ne permet pas de modifier les postes.',
      'POST_STATUS_MANAGED_BY_SESSION' =>
        'Le statut d’un poste occupé est géré par sa session.',
      'POST_HAS_ACTIVE_UNSUPPORTED_GAME' =>
        'Ce poste utilise un jeu actif que vous avez retiré de sa liste.',
      'GAME_NOT_IN_VENUE' =>
        'Un jeu sélectionné n’appartient pas à cette salle.',
      'POST_NOT_FOUND' => 'Ce poste n’existe plus dans cette salle.',
      'INVALID_POST_CONFIGURATION' =>
        'Vérifiez le nom, le type et le nombre de joueurs du poste.',
      'INVALID_PRICE_OVERRIDE' =>
        'Un tarif spécifique est invalide. Utilisez au maximum deux décimales.',
      'PRICE_OVERRIDE_FOR_UNSUPPORTED_GAME' =>
        'Un tarif spécifique concerne un jeu non sélectionné pour ce poste.',
      '23505' => 'Ce numéro de poste me déjà utilisé.',
      'VENUE_NOT_FOUND' => 'Aucune salle n’est associée à votre compte.',
      _ => 'Une erreur est survenue. Réessayez dans quelques instants.',
    };
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

  @override
  Widget build(BuildContext context) {
    final canManage = _venue?.canManageCatalog ?? false;
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final isStaff = (_venue?.role ?? CurrentRoleCache.role) != 'customer';
    return ResponsiveScaffold(
      currentIndex: 1,
      isStaff: isStaff,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _viewModel,
          builder: (context, _) {
            final snapshot = _viewModel.snapshot;
            final posts = snapshot?.posts ?? [];
            final displayError = _error ?? _viewModel.errorMessage;
            return RefreshIndicator(
                    onRefresh: _viewModel.refresh,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 28 : 8,
                        isDesktop ? 24 : 18,
                        isDesktop ? 28 : 8,
                        isDesktop ? 48 : 24,
                      ),
                      children: [
                        AppPageHeader(
                          onBack: () => context.go(_venue?.role == 'customer' ? '/customer/home' : '/home'),
                          trailing: canManage
                              ? IconButton.filled(
                                  tooltip: 'Ajouter un poste',
                                  onPressed: _working ? null : () => _editPost(),
                                  icon: const Icon(Icons.add_rounded),
                                )
                              : null,
                        ),
                        const SizedBox(height: 18),
                        AppScreenTitle(
                          title: 'Postes de jeu',
                          subtitle: snapshot?.venueName ?? 'Gestion de votre salle',
                        ),
                        if (isDesktop && snapshot != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surface1,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.line),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem('Total Postes', '${posts.length}', AppColors.primaryLight),
                                _buildStatItem('Sessions Actives', '${snapshot.sessions.length}', AppColors.green),
                                _buildStatItem('Postes Disponibles', '${posts.where((p) => p.status == 'available').length}', AppColors.blueLight),
                              ],
                            ),
                          ),
                        ],
                        if (displayError != null) ...[
                          const SizedBox(height: 14),
                          _PostNotice(text: displayError, onRetry: _viewModel.refresh),
                        ],
                        if (_viewModel.isLoading && snapshot == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 36),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (posts.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 26),
                            child: _PostEmpty(),
                          )
                        else ...[
                          const SizedBox(height: 18),
                          // Search Bar
                          TextField(
                            controller: _searchController,
                            onChanged: (val) => setState(() => _searchQuery = val),
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Rechercher un poste, jeu ou client...',
                              hintStyle: const TextStyle(fontSize: 13, color: AppColors.muted),
                              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.muted),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: AppColors.surface1,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(color: AppColors.primaryLight),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Filter Chips
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterChip('Tous', 'all'),
                                const SizedBox(width: 8),
                                _buildFilterChip('Disponibles', 'available'),
                                const SizedBox(width: 8),
                                _buildFilterChip('En cours', 'active'),
                                const SizedBox(width: 8),
                                _buildFilterChip('En pause', 'paused'),
                                const SizedBox(width: 8),
                                _buildFilterChip('À encaisser', 'waiting_payment'),
                                const SizedBox(width: 8),
                                _buildFilterChip('Maintenance', 'maintenance'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          (() {
                            final filteredPosts = posts.where((post) {
                              final session = _sessionForPost(snapshot?.sessions ?? [], post.id);
                              final customerName = session?.customerName?.toLowerCase() ?? '';
                              final gameName = session?.game?.name.toLowerCase() ?? '';
                              final postName = post.name.toLowerCase();
                              final device = post.device.toLowerCase();

                              final matchesSearch = _searchQuery.isEmpty ||
                                  postName.contains(_searchQuery.toLowerCase()) ||
                                  device.contains(_searchQuery.toLowerCase()) ||
                                  customerName.contains(_searchQuery.toLowerCase()) ||
                                  gameName.contains(_searchQuery.toLowerCase());

                              final currentStatus = session?.status ?? post.status;
                              final matchesFilter = switch (_filterStatus) {
                                'all' => true,
                                'available' => currentStatus == 'available',
                                'active' => currentStatus == 'active' || currentStatus == 'playing',
                                'paused' => currentStatus == 'paused',
                                'waiting_payment' => currentStatus == 'waiting_payment',
                                'maintenance' => currentStatus == 'maintenance' || currentStatus == 'offline',
                                _ => true,
                              };

                              return matchesSearch && matchesFilter;
                            }).toList();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${filteredPosts.length} / ${posts.length} poste${posts.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          tooltip: _isCarouselView ? 'Mode Grille' : 'Mode Carrousel Immersive',
                                          onPressed: () => setState(() => _isCarouselView = !_isCarouselView),
                                          icon: Icon(
                                            _isCarouselView ? Icons.grid_view_rounded : Icons.view_carousel_rounded,
                                            size: 20,
                                            color: AppColors.primaryLight,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        TextButton.icon(
                                          onPressed: _viewModel.isWorking
                                              ? null
                                              : () {
                                                  if (_venue?.role == 'customer') {
                                                    final available = filteredPosts.where((p) => p.status == 'available' || p.status == 'reserved').toList();
                                                    if (available.isNotEmpty) {
                                                      _requestPostReservation(available.first);
                                                    } else {
                                                      _showMessage('Aucun poste disponible.');
                                                    }
                                                  } else {
                                                    _startSession();
                                                  }
                                                },
                                          icon: Icon((_venue?.role == 'customer') ? Icons.event_available_rounded : Icons.add_rounded),
                                          label: Text((_venue?.role == 'customer') ? 'Demander' : 'Démarrer'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (filteredPosts.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 36),
                                    child: Center(
                                      child: Text(
                                        'Aucun poste ne correspond à votre recherche.',
                                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                                      ),
                                    ),
                                  )
                                else if (_isCarouselView && !isDesktop)
                                  SizedBox(
                                    height: 520,
                                    child: PageView.builder(
                                      controller: _carouselController,
                                      itemCount: filteredPosts.length,
                                      itemBuilder: (context, index) {
                                        final post = filteredPosts[index];
                                        final session = _sessionForPost(
                                          snapshot?.sessions ?? [],
                                          post.id,
                                        );
                                        final isOwnSession = session != null &&
                                            session.customerId != null &&
                                            session.customerId == _currentCustomerId;
                                        final postRequests = (snapshot?.requests ?? [])
                                            .where((r) => r.postId == post.id || (session != null && r.sessionId == session.id))
                                            .toList();
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 2),
                                          child: Stack(
                                            children: [
                                              _PostCard(
                                                post: post,
                                                session: session,
                                                isWorking: _viewModel.isWorking,
                                                promotions: snapshot?.promotions ?? [],
                                                canGiveDiscount: snapshot?.canGiveDiscount ?? false,
                                                isCustomer: _venue?.role == 'customer',
                                                isOwnSession: isOwnSession,
                                                pendingRequests: postRequests,
                                                onDecideRequest: (req, approve) => _viewModel.decideRequest(req, approve: approve),
                                                onStart: () => (_venue?.role == 'customer') ? _requestPostReservation(post) : _startSession(post),
                                                onAction: (action) => _sessionAction(session!, action),
                                              ),
                                              if (canManage)
                                                Positioned(
                                                  top: 8,
                                                  right: 8,
                                                  child: PopupMenuButton<String>(
                                                    enabled: !_working && !_viewModel.isWorking,
                                                    icon: const Icon(
                                                      Icons.more_vert_rounded,
                                                      size: 18,
                                                      color: AppColors.muted,
                                                    ),
                                                    onSelected: (action) {
                                                      if (action == 'edit') {
                                                        _editPost(post);
                                                      } else if (action == 'qr') {
                                                        _showPostQr(post);
                                                      } else {
                                                        _setStatus(
                                                          post,
                                                          action == 'available' ? 'available' : action,
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (context) => [
                                                      const PopupMenuItem(
                                                        value: 'edit',
                                                        child: Text('Modifier le poste'),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'qr',
                                                        child: Text('QR Code Client'),
                                                      ),
                                                      if (session == null && post.status != 'maintenance')
                                                        const PopupMenuItem(
                                                          value: 'maintenance',
                                                          child: Text('Mettre en maintenance'),
                                                        ),
                                                      if (session == null && post.status != 'offline')
                                                        const PopupMenuItem(
                                                          value: 'offline',
                                                          child: Text('Mettre hors ligne'),
                                                        ),
                                                      if (session == null && post.status != 'available')
                                                        const PopupMenuItem(
                                                          value: 'available',
                                                          child: Text('Marquer disponible'),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                else
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final columns = constraints.maxWidth > 1300
                                          ? 4
                                          : constraints.maxWidth > 850
                                              ? 3
                                              : constraints.maxWidth > 520
                                                  ? 2
                                                  : 1;
                                      final cardExtent = constraints.maxWidth > 1300 ? 525.0 : 515.0;
                                      return GridView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: filteredPosts.length,
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                          mainAxisExtent: cardExtent,
                                        ),
                                        itemBuilder: (context, index) {
                                          final post = filteredPosts[index];
                                          final session = _sessionForPost(
                                            snapshot?.sessions ?? [],
                                            post.id,
                                          );
                                          final isOwnSession = session != null &&
                                              session.customerId != null &&
                                              session.customerId == _currentCustomerId;
                                          final postRequests = (snapshot?.requests ?? [])
                                              .where((r) => r.postId == post.id || (session != null && r.sessionId == session.id))
                                              .toList();
                                          return Stack(
                                            children: [
                                              _PostCard(
                                                post: post,
                                                session: session,
                                                isWorking: _viewModel.isWorking,
                                                promotions: snapshot?.promotions ?? [],
                                                canGiveDiscount: snapshot?.canGiveDiscount ?? false,
                                                isCustomer: _venue?.role == 'customer',
                                                isOwnSession: isOwnSession,
                                                pendingRequests: postRequests,
                                                onDecideRequest: (req, approve) => _viewModel.decideRequest(req, approve: approve),
                                                onStart: () => (_venue?.role == 'customer') ? _requestPostReservation(post) : _startSession(post),
                                                onAction: (action) => _sessionAction(session!, action),
                                              ),
                                              if (canManage)
                                                Positioned(
                                                  top: 8,
                                                  right: 8,
                                                  child: PopupMenuButton<String>(
                                                    enabled: !_working && !_viewModel.isWorking,
                                                    icon: const Icon(
                                                      Icons.more_vert_rounded,
                                                      size: 18,
                                                      color: AppColors.muted,
                                                    ),
                                                    onSelected: (action) {
                                                      if (action == 'edit') {
                                                        _editPost(post);
                                                      } else if (action == 'qr') {
                                                        _showPostQr(post);
                                                      } else {
                                                        _setStatus(
                                                          post,
                                                          action == 'available' ? 'available' : action,
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (context) => [
                                                      const PopupMenuItem(
                                                        value: 'edit',
                                                        child: Text('Modifier le poste'),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'qr',
                                                        child: Text('QR Code Client'),
                                                      ),
                                                      if (session == null && post.status != 'maintenance')
                                                        const PopupMenuItem(
                                                          value: 'maintenance',
                                                          child: Text('Mettre en maintenance'),
                                                        ),
                                                      if (session == null && post.status != 'offline')
                                                        const PopupMenuItem(
                                                          value: 'offline',
                                                          child: Text('Mettre hors ligne'),
                                                        ),
                                                      if (session == null && post.status != 'available')
                                                        const PopupMenuItem(
                                                          value: 'available',
                                                          child: Text('Marquer disponible'),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                              ],
                            );
                          }()),
                        ],
                      ],
                    ),
                  );
          },
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? Colors.white : AppColors.muted,
      ),
      backgroundColor: AppColors.surface1,
      selectedColor: AppColors.primary.withValues(alpha: 0.4),
      checkmarkColor: AppColors.primaryLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: isSelected ? AppColors.primaryLight : Colors.white10,
        ),
      ),
      onSelected: (_) => setState(() => _filterStatus = value),
    );
  }

  Future<void> _showPostQr(GamingPost post) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('QR client · ${post.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.qr_code_2_rounded, size: 120, color: AppColors.primaryLight),
              const SizedBox(height: 12),
              Text(
                'Code du poste : ${post.name} (${post.device.toUpperCase()})',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Le client scanne ce code dans l’application pour lier son compte.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
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
  final _customerNameController = TextEditingController();
  final _minutesController = TextEditingController(text: '60');
  bool _linkingCustomer = false;
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
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compatibleGames = _gamesForPost(_post);
    final gameIsAvailable = compatibleGames.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AppSurface(
        borderRadius: 24,
        padding: EdgeInsets.zero,
        child: Container(
          width: 520,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7A2FD6), Color(0xFFC026D3)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nouvelle session de jeu',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Choisissez le poste, le jeu et la durée',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppColors.line),

              // Content Area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Post Selector Section
                      const Text(
                        '1. Choisir le poste de jeu',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<GamingPost>(
                            value: _post,
                            isExpanded: true,
                            dropdownColor: AppColors.surface1,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.text,
                            ),
                            items: widget.posts
                                .map(
                                  (post) => DropdownMenuItem(
                                    value: post,
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.sports_esports_rounded,
                                          size: 18,
                                          color: AppColors.primaryLight,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '${post.name} · ${post.device.toUpperCase()}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _post = value;
                                  final compatible = _gamesForPost(value);
                                  if (compatible.isNotEmpty &&
                                      !value.supportsGame(_game.id)) {
                                    _game = compatible.first;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 2. Game Cards Grid Section
                      const Text(
                        '2. Sélectionner le jeu',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 10),

                      if (!gameIsAvailable)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: AppColors.red,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Aucun jeu compatible avec ce poste.',
                                  style: TextStyle(
                                    color: AppColors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: compatibleGames.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                mainAxisExtent: 85,
                              ),
                          itemBuilder: (context, index) {
                            final game = compatibleGames[index];
                            final isSelected = game.id == _game.id;
                            final price = _post.priceFor(game);
                            final isMatch = game.mode == 'match_based';

                            return GestureDetector(
                              onTap: () => setState(() => _game = game),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary.withValues(
                                          alpha: 0.2,
                                        )
                                      : AppColors.surface2,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primaryLight
                                        : AppColors.line,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            game.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected
                                                  ? Colors.white
                                                  : AppColors.text,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            color: isMatch
                                                ? AppColors.pink.withValues(
                                                    alpha: 0.2,
                                                  )
                                                : AppColors.green.withValues(
                                                    alpha: 0.2,
                                                  ),
                                          ),
                                          child: Text(
                                            isMatch ? 'Match' : 'Temps',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: isMatch
                                                  ? AppColors.pink
                                                  : AppColors.green,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${price.toStringAsFixed(0)} DA',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.primaryLight,
                                          ),
                                        ),
                                        Text(
                                          isMatch
                                              ? '${game.matchMinutes ?? 10} min/match'
                                              : _pricingLabel(game.pricingUnit),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.muted,
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

                      const SizedBox(height: 20),

                      // 3. Customer Selection Section
                      const Text(
                        '3. Client (Nom du client)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AppTextField(
                        hintText: 'Saisissez le nom du client (ex: Karim...)',
                        controller: _customerNameController,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        onChanged: (text) {
                          if (text.isNotEmpty && _customerId != null) {
                            setState(() => _customerId = null);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _customerId,
                            isExpanded: true,
                            dropdownColor: AppColors.surface1,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.text,
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_add_outlined,
                                      size: 18,
                                      color: AppColors.muted,
                                    ),
                                    SizedBox(width: 10),
                                    Text('Ou choisir un compte client existant...'),
                                  ],
                                ),
                              ),
                              ...widget.customers.map(
                                (customer) => DropdownMenuItem<String?>(
                                  value: customer.id,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.person_rounded,
                                        size: 18,
                                        color: AppColors.primaryLight,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        customer.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _customerId = value;
                                if (value != null) {
                                  _customerNameController.clear();
                                }
                              });
                            },
                          ),
                        ),
                      ),

                      if (gameIsAvailable) ...[
                        const SizedBox(height: 20),

                        // 4. Duration Selector Section
                        () {
                          final gName = _game.name.toLowerCase();
                          final isFootball = _game.mode == 'match_based' ||
                              _game.pricingUnit == 'per_match' ||
                              gName.contains('fifa') ||
                              gName.contains('efootball') ||
                              gName.contains('pes') ||
                              gName.contains('fc');

                          if (isFootball) {
                            final footballDurations = [6, 8, 10, 16];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.sports_soccer_rounded,
                                      size: 18,
                                      color: AppColors.pink,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '4. Durée du Match (6, 8, 10, 16 min)',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: footballDurations.map((mins) {
                                    final isSelected =
                                        _selectedFootballMatchMins == mins;
                                    final tierPrice =
                                        _game.pricingTiers[mins.toString()] ??
                                            _game.price;
                                    return ChoiceChip(
                                      label: Text(
                                        '$mins min (${tierPrice.toStringAsFixed(0)} DA)',
                                      ),
                                      selected: isSelected,
                                      selectedColor: AppColors.pink,
                                      backgroundColor: AppColors.surface2,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.muted,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                      ),
                                      onSelected: (_) => setState(() {
                                        _selectedFootballMatchMins = mins;
                                        _minutesController.text =
                                            (mins * _footballMatchCount)
                                                .toString();
                                      }),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface2,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.line),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Nombre de Matchs (${_selectedFootballMatchMins}m / match) :',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            onPressed: () => setState(() {
                                              if (_footballMatchCount > 1) {
                                                _footballMatchCount--;
                                                _minutesController.text =
                                                    (_selectedFootballMatchMins *
                                                            _footballMatchCount)
                                                        .toString();
                                              }
                                            }),
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                              size: 20,
                                              color: AppColors.primaryLight,
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Text(
                                              '$_footballMatchCount',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => setState(() {
                                              _footballMatchCount++;
                                              _minutesController.text =
                                                  (_selectedFootballMatchMins *
                                                          _footballMatchCount)
                                                      .toString();
                                            }),
                                            icon: const Icon(
                                              Icons.add_circle_outline,
                                              size: 20,
                                              color: AppColors.primaryLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                AppTextField(
                                  hintText: 'Ou durée personnalisée en minutes',
                                  controller: _minutesController,
                                  keyboardType: TextInputType.number,
                                  prefixIcon: const Icon(Icons.timer_outlined),
                                  suffixIcon: const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Text(
                                      'minutes',
                                      style: TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '4. Durée de la session',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: () {
                                  final defaultMins = [
                                    30,
                                    60,
                                    90,
                                    120,
                                    180,
                                    240,
                                  ];
                                  final tierMins = _game.pricingTiers.keys
                                      .map((k) => int.tryParse(k) ?? 0)
                                      .where((m) => m > 0);
                                  final allMins = {
                                    ...defaultMins,
                                    ...tierMins,
                                  }.toList()..sort();
                                  return allMins.map((mins) {
                                    final isSelected =
                                        _minutesController.text ==
                                            mins.toString();
                                    final tierPrice =
                                        _game.pricingTiers[mins.toString()];
                                    final label = mins >= 60
                                        ? '${mins ~/ 60}h${mins % 60 > 0 ? '${mins % 60}' : ''}'
                                        : '$mins min';
                                    final displayLabel = tierPrice != null
                                        ? '$label (${tierPrice.toStringAsFixed(0)} DA)'
                                        : label;
                                    return ChoiceChip(
                                      label: Text(displayLabel),
                                      selected: isSelected,
                                      selectedColor: AppColors.primary,
                                      backgroundColor: AppColors.surface2,
                                      labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.muted,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                      ),
                                      onSelected: (_) => setState(
                                        () => _minutesController.text =
                                            mins.toString(),
                                      ),
                                    );
                                  }).toList();
                                }(),
                              ),
                              const SizedBox(height: 10),
                              AppTextField(
                                hintText: 'Durée en minutes (ex: 60)',
                                controller: _minutesController,
                                keyboardType: TextInputType.number,
                                prefixIcon: const Icon(Icons.timer_outlined),
                                suffixIcon: const Padding(
                                                                 padding: EdgeInsets.only(right: 8),
                                  child: Text(
                                    'minutes',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }(),
                      ],
                    ],
                  ),
                ),
              ),

              const Divider(height: 1, color: AppColors.line),

              // Footer Actions
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                      ),
                      child: const Text('Annuler'),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 160,
                      child: AppButton(
                        label: _linkingCustomer ? 'Connexion…' : 'Démarrer',
                        onPressed: (!gameIsAvailable || _linkingCustomer)
                            ? () {}
                            : () async {
                                final minutes = int.tryParse(
                                  _minutesController.text,
                                );

                                String? finalCustId = _customerId;
                                final typedName =
                                    _customerNameController.text.trim();
                                if (finalCustId == null &&
                                    typedName.isNotEmpty) {
                                  setState(() => _linkingCustomer = true);
                                  try {
                                    final client = Supabase.instance.client;
                                    final venue = await VenueRepository(client)
                                        .currentVenue();
                                    final existing = await client
                                        .from('customers')
                                        .select('id')
                                        .eq('venue_id', venue.id)
                                        .ilike('full_name', typedName)
                                        .limit(1);
                                    if (existing.isNotEmpty) {
                                      finalCustId =
                                          existing.first['id'] as String;
                                    } else {
                                      final newCust = await client
                                          .from('customers')
                                          .insert({
                                            'venue_id': venue.id,
                                            'full_name': typedName,
                                          })
                                          .select('id')
                                          .single();
                                      finalCustId = newCust['id'] as String;
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      'Erreur liaison client au démarrage : $e',
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => _linkingCustomer = false,
                                      );
                                    }
                                  }
                                }

                                if (!context.mounted) return;

                                Navigator.pop(
                                  context,
                                  _StartSessionSelection(
                                    post: _post,
                                    game: _game,
                                    customerId: finalCustId,
                                    initialMinutes: minutes ?? 60,
                                  ),
                                );
                              },
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pricingLabel(String? unit) => switch (unit) {
    'per_match' => 'par match',
    'per_minute' => 'par min',
    'per_15_minutes' => 'par 15m',
    'per_30_minutes' => 'par 30m',
    'fixed_price' => 'forfait',
    _ => 'par heure',
  };

  List<CatalogGame> _gamesForPost(GamingPost post) => widget.games
      .where((game) => post.supportsGame(game.id))
      .toList();
}

class _TransferSessionDialog extends StatefulWidget {
  const _TransferSessionDialog({required this.posts});

  final List<GamingPost> posts;

  @override
  State<_TransferSessionDialog> createState() => _TransferSessionDialogState();
}

class _TransferSessionDialogState extends State<_TransferSessionDialog> {
  late GamingPost _target = widget.posts.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Transférer la session'),
      content: DropdownButtonFormField<GamingPost>(
        initialValue: _target,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Nouveau poste'),
        items: widget.posts
            .map(
              (post) => DropdownMenuItem(
                value: post,
                child: Text('${post.name} · ${post.device.toUpperCase()}'),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => _target = value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _target),
          child: const Text('Transférer'),
        ),
      ],
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
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter un produit'),
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
                      '${product.name} · ${product.price.toStringAsFixed(2)} DA '
                      '(${product.stockQuantity} en stock)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _product = value;
                  if (_quantity > value.stockQuantity) {
                    _quantity = value.stockQuantity;
                  }
                });
              }
            },
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Quantité'),
              Row(
                children: [
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text(
                    '$_quantity',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    onPressed: _quantity < _product.stockQuantity
                        ? () => setState(() => _quantity++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _SessionProductSelection(
              product: _product,
              quantity: _quantity,
            ),
          ),
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

class _SessionPaymentDialog extends StatefulWidget {
  const _SessionPaymentDialog({
    required this.session,
    required this.orderItems,
    required this.canManageCredit,
  });

  final ActiveGamingSession session;
  final List<Map<String, dynamic>> orderItems;
  final bool canManageCredit;

  @override
  State<_SessionPaymentDialog> createState() => _SessionPaymentDialogState();
}

class _SessionPaymentDialogState extends State<_SessionPaymentDialog> {
  int _selectedMode = 0; // 0 = Cash/Card, 1 = Debt
  late final _cash = TextEditingController(
    text: widget.session.balanceDue.toStringAsFixed(2),
  );
  final _card = TextEditingController();
  final _wallet = TextEditingController();
  final _credit = TextEditingController();
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
      final balance = widget.session.balanceDue;
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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final balance = session.balanceDue;
    final totalEntered = _entered('cash') +
        _entered('card') +
        _entered('wallet') +
        _entered('credit');
    final hasCustomer = session.customerId != null;
    final needsDebtName = _selectedMode == 1 && !hasCustomer;
    final debtNameValid =
        !needsDebtName || _debtCustomerNameController.text.trim().isNotEmpty;
    final valid = (totalEntered - balance).abs() < 0.01 && debtNameValid;

    return AlertDialog(
      title: Text('Facture & Règlement · ${session.postName ?? 'Poste'}'),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.surface1.withValues(alpha: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Jeu : ${session.game?.name ?? 'Jeu'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('Client : ${session.customerName ?? 'Client sans compte'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Temps / Matchs de jeu', style: TextStyle(fontSize: 12)),
                    Text('${session.gamingTotal.toStringAsFixed(2)} DA', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (widget.orderItems.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text('Produits & Bar commandés', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryLight)),
                  const SizedBox(height: 4),
                  ...widget.orderItems.map((item) {
                    final product = item['products'] is Map ? item['products'] as Map : {};
                    final name = product['name'] as String? ?? 'Produit';
                    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                    final total = (item['line_total'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$name (x$qty)', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          Text('${total.toStringAsFixed(2)} DA', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    );
                  }),
                ],
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Général', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('${(session.gamingTotal + session.productsTotal).toStringAsFixed(2)} DA', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pink)),
                  ],
                ),
                const SizedBox(height: 16),

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
                      labelText: 'Espèces (Cash)',
                      suffixText: 'DA',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _card,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Carte bancaire',
                      suffixText: 'DA',
                    ),
                  ),
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
                const SizedBox(height: 14),
                Text(
                  'Montant validé : ${totalEntered.toStringAsFixed(2)} / ${balance.toStringAsFixed(2)} DA',
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
    final balance = widget.session.balanceDue;
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

        // Check if customer with this name already exists in venue
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e')),
          );
          setState(() => _creatingCustomer = false);
        }
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
    if (mounted) Navigator.pop(context, lines);
  }
}

class _SessionPromotionDialog extends StatefulWidget {
  const _SessionPromotionDialog({required this.promotions});

  final List<SessionPromotion> promotions;

  @override
  State<_SessionPromotionDialog> createState() => _SessionPromotionDialogState();
}

class _SessionPromotionDialogState extends State<_SessionPromotionDialog> {
  late SessionPromotion _promotion = widget.promotions.first;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Appliquer une promotion'),
      content: DropdownButtonFormField<SessionPromotion>(
        initialValue: _promotion,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Promotion'),
        items: widget.promotions
            .map(
              (promotion) => DropdownMenuItem(
                value: promotion,
                child: Text(
                  '${promotion.name} · -${promotion.discountPercent}%',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => _promotion = value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _promotion),
          child: const Text('Appliquer'),
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.color,
    this.backgroundColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool enabled;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Colors.white;
    final bg = backgroundColor ?? Colors.white.withValues(alpha: 0.14);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: enabled ? bg : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: enabled
                    ? (color?.withValues(alpha: 0.45) ??
                        Colors.white.withValues(alpha: 0.3))
                    : AppColors.line,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: (color ?? AppColors.primary).withValues(
                          alpha: 0.3,
                        ),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? iconColor : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

String _requestLabel(PendingSessionRequest req) {
  switch (req.type) {
    case 'match':
      final qty = req.payload['qty'] ?? 1;
      return '+$qty match${qty > 1 ? 's' : ''}';
    case 'time':
      if (req.payload['pause_requested'] == true) {
        return 'Pause';
      }
      final mins = req.payload['minutes'] ?? 30;
      return '+$mins min';
    case 'product':
      final name = req.payload['product_name'] ?? 'Produit/Snack';
      final qty = req.payload['quantity'] ?? 1;
      return '$qty x $name';
    case 'start_session':
      return 'Démarrage session';
    case 'checkout':
      return 'Fin de session';
    default:
      return 'Demande';
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
    this.isCustomer = false,
    this.isOwnSession = false,
    this.pendingRequests = const [],
    this.onDecideRequest,
    required this.onStart,
    required this.onAction,
  });

  final GamingPost post;
  final ActiveGamingSession? session;
  final bool isWorking;
  final List<SessionPromotion> promotions;
  final bool canGiveDiscount;
  final bool isCustomer;
  final bool isOwnSession;
  final List<PendingSessionRequest> pendingRequests;
  final void Function(PendingSessionRequest request, bool approve)? onDecideRequest;
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

    final game = session?.game;
    final gameYoutubeUrl = game?.youtubeUrl;
    final gameImageUrl = game?.imageUrl;
    final hasGameVideo = gameYoutubeUrl != null && gameYoutubeUrl.isNotEmpty;
    final hasGameImage = gameImageUrl != null && gameImageUrl.isNotEmpty;

    final cardStack = Stack(
      fit: StackFit.expand,
      children: [
              // 1. Full Card Game Cover Background Image or YouTube Media
              if (hasGameVideo)
                InteractivePostCardMedia(
                  coverImageUrl: gameImageUrl,
                  youtubeUrl: gameYoutubeUrl,
                  title: post.name,
                  subtitle: game?.name,
                )
              else if (hasGameImage)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                  child: Image.network(
                    gameImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.surface1,
                    ),
                  ),
                )
              else
                const ColoredBox(color: AppColors.surface1),

              // 2. Glassmorphic Dark Overlay for contrast
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),

              // 3. Stunning Glossy Lighting Reflection Effect (Specular Sheen & Glow)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0.08),
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.04),
                        ],
                        stops: const [0.0, 0.15, 0.5, 1.0],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Card Content Overlay
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Header Row: Post Name & Status Badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black45,
                            border: Border.all(color: Colors.white24),
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '${post.device.toUpperCase()} · Poste ${post.number}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: statusColor.withValues(alpha: 0.25),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.5),
                            ),
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

                    if (hasSession) ...[
                      // Game & Customer Line
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${session!.game?.name ?? 'Jeu'} · ${session!.customerName ?? 'Client de passage'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: session!.game?.mode == 'match_based'
                                  ? AppColors.pink.withValues(alpha: 0.3)
                                  : AppColors.primary.withValues(alpha: 0.3),
                            ),
                            child: Text(
                              session!.game?.mode == 'match_based'
                                  ? 'Matchs'
                                  : 'Temps',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: session!.game?.mode == 'match_based'
                                    ? AppColors.pink
                                    : AppColors.primaryLight,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Center Prominent Glowing Countdown Clock
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
                              color: statusColor.withValues(alpha: 0.7),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.35),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_rounded,
                                size: 18,
                                color: statusColor,
                              ),
                              const SizedBox(width: 8),
                              _StaffSessionCountdown(
                                session: session!,
                                isMatchBased:
                                    session!.game?.mode == 'match_based',
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Financial Total Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Jeux: ${session!.gamingTotal.toStringAsFixed(0)} DA · Bar: ${session!.productsTotal.toStringAsFixed(0)} DA',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white60,
                            ),
                          ),
                          Text(
                            'Total: ${(session!.gamingTotal + session!.productsTotal).toStringAsFixed(0)} DA',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.pink,
                            ),
                          ),
                        ],
                      ),

                      if (pendingRequests.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.amber, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_active_rounded, color: AppColors.amber, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Demande: ${_requestLabel(pendingRequests.first)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Par ${pendingRequests.first.customerName}',
                                      style: const TextStyle(fontSize: 10, color: AppColors.muted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isCustomer && onDecideRequest != null) ...[
                                InkWell(
                                  onTap: isWorking ? null : () => onDecideRequest!(pendingRequests.first, true),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.check_circle_rounded, color: AppColors.green, size: 24),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: isWorking ? null : () => onDecideRequest!(pendingRequests.first, false),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.cancel_rounded, color: AppColors.red, size: 24),
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.amber.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'En attente',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.amber),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      // Engraved Glassmorphic Icon-Only Action Bar
                      if (!isCustomer)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (session!.status == 'waiting_payment') ...[
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: isWorking
                                      ? null
                                      : () => onAction('pay_session'),
                                  icon: const Icon(
                                    Icons.payments_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    session!.balanceDue > 0
                                        ? 'Encaisser ${session!.balanceDue.toStringAsFixed(0)} DA'
                                        : 'Clôturer',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              if (canGiveDiscount &&
                                  promotions.isNotEmpty &&
                                  !session!.promotionApplied) ...[
                                const SizedBox(width: 8),
                                _GlassIconButton(
                                  icon: Icons.local_offer_outlined,
                                  tooltip: 'Promotion',
                                  color: AppColors.amber,
                                  enabled: !isWorking,
                                  onPressed: () => onAction('apply_promotion'),
                                ),
                              ],
                            ] else ...[
                              _GlassIconButton(
                                icon: Icons.add_shopping_cart_rounded,
                                tooltip: 'Ajouter un produit (Bar)',
                                color: AppColors.blueLight,
                                enabled:
                                    !isWorking && session!.status == 'active',
                                onPressed: () => onAction('add_product'),
                              ),
                              if (session!.game?.mode == 'match_based')
                                _GlassIconButton(
                                  icon: Icons.sports_esports_rounded,
                                  tooltip: 'Ajouter un match',
                                  color: AppColors.primaryLight,
                                  enabled:
                                      !isWorking && session!.status == 'active',
                                  onPressed: () => onAction('add_match'),
                                )
                              else
                                _GlassIconButton(
                                  icon: Icons.more_time_rounded,
                                  tooltip: 'Ajouter du temps',
                                  color: AppColors.primaryLight,
                                  enabled:
                                      !isWorking && session!.status == 'active',
                                  onPressed: () => onAction('add_time'),
                                ),
                              _GlassIconButton(
                                icon: session!.status == 'paused'
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                tooltip: session!.status == 'paused'
                                    ? 'Reprendre'
                                    : 'Mettre en pause',
                                color: session!.status == 'paused'
                                    ? AppColors.green
                                    : AppColors.amber,
                                enabled: !isWorking,
                                onPressed: () => onAction(
                                  session!.status == 'paused'
                                      ? 'resume_session'
                                      : 'pause_session',
                                ),
                              ),
                              _GlassIconButton(
                                icon: Icons.swap_horiz_rounded,
                                tooltip: 'Transférer la session',
                                color: AppColors.blueLight,
                                enabled: !isWorking,
                                onPressed: () => onAction('transfer_session'),
                              ),
                              _GlassIconButton(
                                icon: Icons.stop_rounded,
                                tooltip: 'Terminer la session',
                                color: AppColors.red,
                                backgroundColor:
                                    AppColors.red.withValues(alpha: 0.25),
                                enabled: !isWorking,
                                onPressed: () => onAction('end_session'),
                              ),
                            ],
                          ],
                        )
                      else if (isOwnSession)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _GlassIconButton(
                              icon: Icons.add_shopping_cart_rounded,
                              tooltip: 'Commander Bar',
                              color: AppColors.blueLight,
                              enabled: !isWorking && session!.status == 'active',
                              onPressed: () => onAction('customer_request_product'),
                            ),
                            if (session!.game?.mode == 'match_based')
                              _GlassIconButton(
                                icon: Icons.sports_esports_rounded,
                                tooltip: 'Demander Match / مباراة',
                                color: AppColors.primaryLight,
                                enabled: !isWorking && session!.status == 'active',
                                onPressed: () => onAction('add_match'),
                              )
                            else
                              _GlassIconButton(
                                icon: Icons.more_time_rounded,
                                tooltip: 'Demander Temps / تمديد',
                                color: AppColors.primaryLight,
                                enabled: !isWorking && session!.status == 'active',
                                onPressed: () => onAction('customer_request_time'),
                              ),
                            _GlassIconButton(
                              icon: Icons.pause_rounded,
                              tooltip: 'Demander Pause / توقيف',
                              color: AppColors.amber,
                              enabled: !isWorking,
                              onPressed: () => onAction('customer_request_pause'),
                            ),
                            _GlassIconButton(
                              icon: Icons.stop_rounded,
                              tooltip: 'Demander Fin / إنهاء',
                              color: AppColors.red,
                              backgroundColor: AppColors.red.withValues(alpha: 0.25),
                              enabled: !isWorking,
                              onPressed: () => onAction('customer_request_end'),
                            ),
                          ],
                        ),
                    ] else ...[
                      // Free Post State
                      Center(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.videogame_asset_off_outlined,
                              size: 32,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Poste libre',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (pendingRequests.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.amber, width: 1.2),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_active_rounded, color: AppColors.amber, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Demande: ${_requestLabel(pendingRequests.first)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Par ${pendingRequests.first.customerName}',
                                      style: TextStyle(fontSize: 10, color: AppColors.muted),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (!isCustomer && onDecideRequest != null) ...[
                                InkWell(
                                  onTap: isWorking ? null : () => onDecideRequest!(pendingRequests.first, true),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.check_circle_rounded, color: AppColors.green, size: 24),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: isWorking ? null : () => onDecideRequest!(pendingRequests.first, false),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.cancel_rounded, color: AppColors.red, size: 24),
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.amber.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'En attente',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.amber),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isWorking ||
                                  (post.status != 'available' &&
                                      post.status != 'reserved')
                              ? null
                              : onStart,
                          icon: Icon(isCustomer ? Icons.event_available_rounded : Icons.play_arrow_rounded, size: 18),
                          label: Text(isCustomer ? 'Réserver ce poste' : 'Démarrer une session'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

    return AppSurface(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: double.infinity,
          height: 385,
          child: cardStack,
        ),
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
  bool _hasAlerted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    _checkAlert();
  }

  @override
  void didUpdateWidget(covariant _StaffSessionCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      _hasAlerted = false;
    }
    if (oldWidget.session.status != widget.session.status ||
        oldWidget.session.id != widget.session.id ||
        oldWidget.session.plannedDurationSeconds != widget.session.plannedDurationSeconds) {
      _startTimer();
    }
    _checkAlert();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.session.status == 'active' &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          _checkAlert();
          setState(() {});
        }
      });
    }
  }

  void _checkAlert() {
    if (!mounted) return;
    final remainingSecs = widget.session.remainingSeconds(DateTime.now());
    if (remainingSecs > 0) {
      _hasAlerted = false;
    } else if (remainingSecs <= 0 &&
        widget.session.status == 'active' &&
        !_hasAlerted) {
      _hasAlerted = true;
      try {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _checkAlert();
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
    final remainingSecs = widget.session.remainingSeconds(DateTime.now());
    final remaining = _formatDuration(remainingSecs);
    return Text(
      widget.isMatchBased
          ? 'Matchs : ${widget.session.matchCount} · $remaining restantes'
          : '$remaining restantes',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: AppColors.blueLight, fontWeight: FontWeight.w700),
    );
  }
}

String _formatDuration(int totalSeconds) {
  if (totalSeconds <= 0) return '00:00';
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

class _PostNotice extends StatelessWidget {
  const _PostNotice({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ),
        IconButton(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.red),
        ),
      ],
    ),
  );
}

class _PostEmpty extends StatelessWidget {
  const _PostEmpty();

  @override
  Widget build(BuildContext context) => const AppSurface(
    borderRadius: 20,
    child: Column(
      children: [
        Icon(Icons.sports_esports_rounded, size: 36, color: AppColors.muted),
        SizedBox(height: 12),
        Text(
          'Aucun poste configuré',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text(
          'Ajoutez vos postes de jeu pour démarrer les premières sessions.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
  );
}

String _statusLabel(String status) => switch (status) {
  'available' => 'DISPONIBLE',
  'reserved' => 'RÉSERVÉ',
  'starting' => 'DÉMARRAGE',
  'playing' => 'EN COURS',
  'paused' => 'EN PAUSE',
  'waiting_payment' => 'PAIEMENT',
  'maintenance' => 'MAINTENANCE',
  'offline' => 'HORS LIGNE',
  _ => status.toUpperCase(),
};

class _PostFormValue {
  const _PostFormValue({
    required this.name,
    required this.device,
    required this.maxPlayers,
    required this.zone,
    required this.supportedGameIds,
    required this.priceOverrides,
  });

  final String name;
  final String device;
  final int maxPlayers;
  final String zone;
  final Set<String> supportedGameIds;
  final Map<String, double> priceOverrides;
}

class _PostFormDialog extends StatefulWidget {
  const _PostFormDialog({
    required this.nextNumber,
    required this.games,
    required this.supportedGameIds,
    required this.priceOverrides,
    this.existing,
  });

  final int nextNumber;
  final List<Map<String, dynamic>> games;
  final Set<String> supportedGameIds;
  final Map<String, double> priceOverrides;
  final GamingPost? existing;

  @override
  State<_PostFormDialog> createState() => _PostFormDialogState();
}

class _PostFormDialogState extends State<_PostFormDialog> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? 'POST ${widget.nextNumber}',
  );
  late final _zone = TextEditingController(
    text: '',
  );
  late final _youtubeUrl = TextEditingController(
    text: widget.existing?.youtubeUrl ?? '',
  );
  late String _device = widget.existing?.device ?? 'ps5';
  late int _players = widget.existing?.maxPlayers ?? 2;
  late final Set<String> _supportedGameIds = {...widget.supportedGameIds};
  late final Map<String, TextEditingController> _priceControllers = {
    for (final game in widget.games)
      game['id'] as String: TextEditingController(
        text: widget.priceOverrides[game['id']]?.toStringAsFixed(2) ?? '',
      ),
  };
  String? _priceError;

  @override
  void initState() {
    super.initState();
    for (final controller in _priceControllers.values) {
      controller.addListener(() {
        if (_priceError != null) {
          setState(() => _priceError = null);
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _zone.dispose();
    _youtubeUrl.dispose();
    for (final controller in _priceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const devices = [
      {'id': 'ps5', 'label': 'PlayStation 5', 'icon': Icons.sports_esports_rounded},
      {'id': 'ps4', 'label': 'PlayStation 4', 'icon': Icons.sports_esports_outlined},
      {'id': 'xbox', 'label': 'Xbox', 'icon': Icons.gamepad_rounded},
      {'id': 'pc', 'label': 'PC', 'icon': Icons.computer_rounded},
      {'id': 'vr', 'label': 'VR', 'icon': Icons.vrpano_rounded},
      {'id': 'other', 'label': 'Autre', 'icon': Icons.devices_other_rounded},
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AppSurface(
        borderRadius: 24,
        padding: EdgeInsets.zero,
        child: Container(
          width: 520,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7A2FD6), Color(0xFFC026D3)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.tv_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.existing == null
                                ? 'Ajouter un poste'
                                : 'Modifier le poste',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Configurez les détails du poste et les jeux compatibles',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppColors.line),

              // Content Area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. General Details
                      const Text(
                        '1. Informations générales',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AppTextField(
                        hintText: 'Nom du poste (ex: POST 1)',
                        controller: _name,
                        prefixIcon: const Icon(Icons.tv_rounded),
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        hintText: 'Zone (facultatif, ex: VIP, Salon A)',
                        controller: _zone,
                        prefixIcon: const Icon(Icons.map_outlined),
                      ),

                      const SizedBox(height: 20),

                      // 2. Device Type Selection Cards
                      const Text(
                        '2. Type de poste / Console',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: devices.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              mainAxisExtent: 65,
                            ),
                        itemBuilder: (context, index) {
                          final dev = devices[index];
                          final isSelected = _device == dev['id'];
                          return GestureDetector(
                            onTap: () => setState(
                              () => _device = dev['id'] as String,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primaryLight
                                      : AppColors.line,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    dev['icon'] as IconData,
                                    size: 18,
                                    color: isSelected
                                        ? AppColors.primaryLight
                                        : AppColors.muted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      dev['label'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? Colors.white
                                            : AppColors.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // 3. Player Count Selection Chips
                      const Text(
                        '3. Nombre de joueurs maximum',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [1, 2, 4, 6, 8].map((count) {
                          final isSelected = _players == count;
                          return ChoiceChip(
                            label: Text('$count joueurs'),
                            selected: isSelected,
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.surface2,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.muted,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                            onSelected: (_) => setState(() => _players = count),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 20),

                      // 4. Compatible Games & Specific Pricing
                      const Text(
                        '4. Jeux compatibles & Tarifs spécifiques',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_priceError != null) ...[
                        Text(
                          _priceError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (widget.games.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: const Text(
                            'Aucun jeu dans le catalogue. Ajoutez des jeux pour les associer.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        )
                      else
                        ...widget.games.map((game) {
                          final gameId = game['id'] as String;
                          final price = (game['price'] as num).toDouble();
                          final selected = _supportedGameIds.contains(gameId);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.surface2
                                  : AppColors.surface1.withValues(
                                      alpha: 0.4,
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primaryLight.withValues(
                                        alpha: 0.5,
                                      )
                                    : AppColors.line,
                              ),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: selected,
                                      activeColor: AppColors.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      onChanged: (value) => setState(() {
                                        if (value == true) {
                                          _supportedGameIds.add(gameId);
                                        } else {
                                          _supportedGameIds.remove(gameId);
                                        }
                                      }),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            game['name'] as String,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.text,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Catalogue : ${price.toStringAsFixed(0)} DA · ${_pricingLabel(game['pricing_unit'] as String?)}',
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
                                if (selected) ...[
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 36),
                                    child: AppTextField(
                                      hintText:
                                          'Tarif spécifique (défaut: ${price.toStringAsFixed(0)} DA)',
                                      controller: _priceControllers[gameId],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      prefixIcon: const Icon(
                                        Icons.payments_outlined,
                                        size: 16,
                                      ),
                                      suffixIcon: const Padding(
                                        padding: EdgeInsets.only(right: 8),
                                        child: Text(
                                          'DA',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1, color: AppColors.line),

              // Footer Actions
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.muted,
                      ),
                      child: const Text('Annuler'),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 140,
                      child: AppButton(
                        label: 'Enregistrer',
                        onPressed: _save,
                        icon: const Icon(Icons.check_rounded, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pricingLabel(String? unit) => switch (unit) {
    'per_match' => 'par match',
    'per_minute' => 'par minute',
    'per_15_minutes' => 'par 15 min',
    'per_30_minutes' => 'par 30 min',
    'fixed_price' => 'forfait fixe',
    _ => 'par heure',
  };

  void _save() {
    setState(() => _priceError = null);
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final priceOverrides = <String, double>{};
    for (final gameId in _supportedGameIds) {
      final text = _priceControllers[gameId]?.text.trim() ?? '';
      if (text.isEmpty) continue;
      final price = double.tryParse(text.replaceAll(',', '.'));
      if (price == null ||
          !price.isFinite ||
          price < 0 ||
          ((price * 100) - (price * 100).round()).abs() > 0.000001) {
        setState(
          () => _priceError = 'Saisissez un tarif valide (2 décimales max).',
        );
        return;
      }
      priceOverrides[gameId] = price;
    }
    Navigator.pop(
      context,
      _PostFormValue(
        name: name,
        device: _device,
        maxPlayers: _players,
        zone: _zone.text.trim(),
        supportedGameIds: Set.unmodifiable(_supportedGameIds),
        priceOverrides: Map.unmodifiable(priceOverrides),
      ),
    );
  }
}

class _SessionReceiptDialog extends StatelessWidget {
  const _SessionReceiptDialog({
    required this.session,
    required this.orderItems,
  });

  final ActiveGamingSession session;
  final List<Map<String, dynamic>> orderItems;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Facture finale · ${session.postName ?? 'Poste'}'),
      content: SizedBox(
        width: 400,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 500),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.surface1.withValues(alpha: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Jeu : ${session.game?.name ?? 'Jeu'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('Client : ${session.customerName ?? 'Client sans compte'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Détails des prestations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Temps / Matchs de jeu', style: TextStyle(fontSize: 12)),
                    Text('${session.gamingTotal.toStringAsFixed(2)} DA', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                if (orderItems.isNotEmpty) ...[
                  const Divider(height: 16),
                  const Text('Produits & Bar commandés', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primaryLight)),
                  const SizedBox(height: 6),
                  ...orderItems.map((item) {
                    final product = item['products'] is Map ? item['products'] as Map : {};
                    final name = product['name'] as String? ?? 'Produit';
                    final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                    final total = (item['line_total'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$name (x$qty)', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                          Text('${total.toStringAsFixed(2)} DA', style: const TextStyle(fontSize: 11.5)),
                        ],
                      ),
                    );
                  }),
                ],
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Général', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    Text('${(session.gamingTotal + session.productsTotal).toStringAsFixed(2)} DA', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.pink)),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Voulez-vous clôturer ce poste et valider la facture ?', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirmer et encaisser'),
        ),
      ],
    );
  }
}

class _Post3DCarouselReel extends StatefulWidget {
  const _Post3DCarouselReel({
    required this.posts,
    required this.sessions,
    required this.promotions,
    required this.canGiveDiscount,
    required this.canManage,
    required this.isWorking,
    required this.controller,
    required this.onStart,
    required this.onAction,
    required this.onEditPost,
    required this.onShowQr,
    required this.onSetStatus,
  });

  final List<GamingPost> posts;
  final List<ActiveGamingSession> sessions;
  final List<SessionPromotion> promotions;
  final bool canGiveDiscount;
  final bool canManage;
  final bool isWorking;
  final PageController controller;
  final ValueChanged<GamingPost> onStart;
  final void Function(ActiveGamingSession, String) onAction;
  final ValueChanged<GamingPost> onEditPost;
  final ValueChanged<GamingPost> onShowQr;
  final void Function(GamingPost, String) onSetStatus;

  @override
  State<_Post3DCarouselReel> createState() => _Post3DCarouselReelState();
}

class _Post3DCarouselReelState extends State<_Post3DCarouselReel> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final page = widget.controller.page?.round() ?? 0;
    if (page != _currentIndex && page >= 0 && page < widget.posts.length) {
      setState(() => _currentIndex = page);
    }
  }

  ActiveGamingSession? _sessionForPost(String postId) {
    for (final session in widget.sessions) {
      if (session.postId == postId) return session;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 3D Stage Reel matching postes_water.html .stage & .scene
        SizedBox(
          height: 520,
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final page = widget.controller.hasClients &&
                      widget.controller.position.haveDimensions
                  ? widget.controller.page ?? 0.0
                  : _currentIndex.toDouble();

              return PageView.builder(
                controller: widget.controller,
                itemCount: widget.posts.length,
                itemBuilder: (context, index) {
                  final post = widget.posts[index];
                  final session = _sessionForPost(post.id);
                  final delta = index - page;
                  final absDelta = delta.abs();

                  // 3D Perspective Calculations (Matching postes_water.html)
                  final rotateY = -delta * 0.45;
                  final scale = (1.0 - (absDelta * 0.06)).clamp(0.75, 1.0);
                  final opacity = (1.0 - (absDelta * 0.35)).clamp(0.4, 1.0);
                  final isCenter = absDelta < 0.5;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001) // perspective
                      ..rotateY(rotateY)
                      ..scale(scale),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        decoration: isCenter
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.45),
                                    blurRadius: 32,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: AppColors.pink.withValues(alpha: 0.25),
                                    blurRadius: 60,
                                    spreadRadius: 4,
                                  ),
                                ],
                              )
                            : null,
                        child: Stack(
                          children: [
                            _PostCard(
                              post: post,
                              session: session,
                              isWorking: widget.isWorking,
                              promotions: widget.promotions,
                              canGiveDiscount: widget.canGiveDiscount,
                              onStart: () => widget.onStart(post),
                              onAction: (action) =>
                                  widget.onAction(session!, action),
                            ),
                            if (widget.canManage)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: PopupMenuButton<String>(
                                  enabled: !widget.isWorking,
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: AppColors.muted,
                                  ),
                                  onSelected: (action) {
                                    if (action == 'edit') {
                                      widget.onEditPost(post);
                                    } else if (action == 'qr') {
                                      widget.onShowQr(post);
                                    } else {
                                      widget.onSetStatus(
                                        post,
                                        action == 'available'
                                            ? 'available'
                                            : action,
                                      );
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Modifier le poste'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'qr',
                                      child: Text('QR Code Client'),
                                    ),
                                    if (session == null &&
                                        post.status != 'maintenance')
                                      const PopupMenuItem(
                                        value: 'maintenance',
                                        child: Text('Mettre en maintenance'),
                                      ),
                                    if (session == null &&
                                        post.status != 'offline')
                                      const PopupMenuItem(
                                        value: 'offline',
                                        child: Text('Mettre hors ligne'),
                                      ),
                                    if (session == null &&
                                        post.status != 'available')
                                      const PopupMenuItem(
                                        value: 'available',
                                        child: Text('Marquer disponible'),
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
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // Controls Matching HTML #prev #next #dots
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton.filledTonal(
                onPressed: _currentIndex > 0
                    ? () => widget.controller.previousPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        )
                    : null,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface2,
                  foregroundColor: AppColors.primaryLight,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.posts.length, (i) {
                  final isSelected = i == _currentIndex;
                  return GestureDetector(
                    onTap: () => widget.controller.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isSelected ? 12 : 8,
                      height: isSelected ? 12 : 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppColors.primaryLight
                            : Colors.white24,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primaryLight
                                      .withValues(alpha: 0.8),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }),
              ),
              IconButton.filledTonal(
                onPressed: _currentIndex < widget.posts.length - 1
                    ? () => widget.controller.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        )
                    : null,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface2,
                  foregroundColor: AppColors.primaryLight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerStartSessionDialog extends StatefulWidget {
  const _CustomerStartSessionDialog({
    required this.initialPost,
    required this.posts,
    required this.games,
    required this.timeZone,
    required this.onRequest,
  });

  final GamingPost initialPost;
  final List<GamingPost> posts;
  final List<CatalogGame> games;
  final String timeZone;
  final Future<void> Function(GamingPost post, CatalogGame game, int durationMinutes) onRequest;

  @override
  State<_CustomerStartSessionDialog> createState() => _CustomerStartSessionDialogState();
}

class _CustomerStartSessionDialogState extends State<_CustomerStartSessionDialog> {
  late GamingPost _post;
  late CatalogGame _game;
  final _minutesController = TextEditingController(text: '60');
  int _selectedMatchMins = 10;
  int _matchCount = 1;
  bool _working = false;
  String? _error;

  List<CatalogGame> _gamesForPost(GamingPost post) {
    return widget.games.where((g) => post.supportsGame(g.id)).toList();
  }

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    final compatible = _gamesForPost(_post);
    _game = compatible.isNotEmpty ? compatible.first : widget.games.first;
    _selectedMatchMins = _game.matchMinutes ?? 10;
    _minutesController.text = (_selectedMatchMins * _matchCount).toString();
  }

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final duration = int.tryParse(_minutesController.text) ?? 60;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.onRequest(_post, _game, _game.mode == 'match_based' ? (_selectedMatchMins * _matchCount) : duration);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _formatRequestErrorHelper(e);
          _working = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compatibleGames = _gamesForPost(_post);
    final gameIsAvailable = compatibleGames.isNotEmpty;
    final isMatchBased = _game.mode == 'match_based';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AppSurface(
        borderRadius: 24,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.sports_esports_rounded, color: AppColors.primaryLight),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Demander une session de jeu',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Poste : ${_post.name}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Poste', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryLight)),
                const SizedBox(height: 8),
                DropdownButtonFormField<GamingPost>(
                  value: _post,
                  isExpanded: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
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
                const SizedBox(height: 16),
                const Text('Jeu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryLight)),
                const SizedBox(height: 8),
                if (!gameIsAvailable)
                  const Text('Aucun jeu compatible avec ce poste.', style: TextStyle(color: AppColors.red, fontSize: 12))
                else
                  DropdownButtonFormField<CatalogGame>(
                    value: compatibleGames.contains(_game) ? _game : compatibleGames.first,
                    isExpanded: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: compatibleGames
                        .map(
                          (game) => DropdownMenuItem(
                            value: game,
                            child: Text(
                              '${game.name} · ${_post.priceFor(game).toStringAsFixed(0)} DA',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _game = value;
                          _selectedMatchMins = value.matchMinutes ?? 10;
                          _minutesController.text = (_selectedMatchMins * _matchCount).toString();
                        });
                      }
                    },
                  ),
                if (gameIsAvailable && (_game.imageUrl != null || (_game.youtubeUrl != null && _game.youtubeUrl!.isNotEmpty))) ...[
                  const SizedBox(height: 14),
                  InteractivePostCardMedia(
                    coverImageUrl: _game.imageUrl,
                    youtubeUrl: _game.youtubeUrl,
                    title: _game.name,
                    subtitle: '${_post.name} · ${_post.priceFor(_game).toStringAsFixed(0)} DA',
                  ),
                ],
                const SizedBox(height: 16),
                if (gameIsAvailable && !isMatchBased) ...[
                  const Text('Durée initiale (minutes)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryLight)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _minutesController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      labelText: 'Minutes',
                    ),
                  ),
                ] else if (gameIsAvailable && isMatchBased) ...[
                  const Text('Nombre de matchs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryLight)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1, 2, 3, 5].map((count) {
                      final isSelected = _matchCount == count;
                      return ChoiceChip(
                        label: Text('$count match${count > 1 ? 's' : ''}'),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.surface2,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.muted,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                        ),
                        onSelected: (_) => setState(() {
                          _matchCount = count;
                          _minutesController.text = (_selectedMatchMins * count).toString();
                        }),
                      );
                    }).toList(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: _working ? 'Envoi en cours…' : 'Envoyer la demande de session',
                    icon: const Icon(Icons.send_rounded, size: 18),
                    onPressed: _working ? () {} : () => _submit(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatRequestErrorHelper(dynamic error) {
  final msg = error.toString().toUpperCase();
  if (msg.contains('REQUEST_ALREADY_PENDING')) {
    return 'Une demande est déjà en attente pour cette session ou ce poste.';
  }
  if (msg.contains('GAME_NOT_TIME_BASED')) {
    return 'Cette session n’est pas basée sur le temps (jeu au match).';
  }
  if (msg.contains('GAME_NOT_MATCH_BASED')) {
    return 'Cette session n’est pas basée sur les matchs.';
  }
  if (msg.contains('SESSION_NOT_ACTIVE')) {
    return 'La session n’est plus active.';
  }
  if (msg.contains('FORBIDDEN') || msg.contains('42501')) {
    return 'Votre rôle ne permet pas d’effectuer cette opération.';
  }
  if (msg.contains('REQUEST_TYPE_NOT_SUPPORTED')) {
    return 'Ce type de demande n’est pas pris en charge.';
  }
  if (msg.contains('POST_NOT_AVAILABLE')) {
    return 'Ce poste n’est plus disponible.';
  }
  if (msg.contains('GAME_NOT_AVAILABLE')) {
    return 'Ce jeu n’est pas disponible.';
  }
  return 'Impossible d’envoyer la demande. Réessayez.';
}
