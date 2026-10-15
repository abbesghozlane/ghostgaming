import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../domain/session_dashboard_models.dart';

class SessionDashboardSnapshot {
  const SessionDashboardSnapshot({
    required this.venueId,
    required this.venueName,
    required this.timeZone,
    required this.canManageCredit,
    required this.canGiveDiscount,
    required this.canManagePromotions,
    required this.posts,
    required this.games,
    required this.customers,
    required this.promotions,
    required this.sessions,
    required this.requests,
    required this.standaloneOrderRequests,
    required this.products,
  });

  final String venueId;
  final String venueName;
  final String timeZone;
  final bool canManageCredit;
  final bool canGiveDiscount;
  final bool canManagePromotions;
  final List<GamingPost> posts;
  final List<CatalogGame> games;
  final List<VenueCustomer> customers;
  final List<SessionPromotion> promotions;
  final List<ActiveGamingSession> sessions;
  final List<PendingSessionRequest> requests;
  final List<PendingStandaloneOrderRequest> standaloneOrderRequests;
  final List<SessionProduct> products;
}

class SessionDashboardRepository {
  SessionDashboardRepository(this._client);

  final SupabaseClient _client;

  Future<SessionDashboardSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    final venueId = venue.id;

    final now = DateTime.now().toUtc().toIso8601String();
    final results = await Future.wait([
      _client
          .from('posts')
          .select(
            'id, name, number, device, status, youtube_url, post_games(game_id), '
            'post_game_prices(game_id, price_override)',
          )
          .eq('venue_id', venueId)
          .order('number'),
      _client
          .from('games')
          .select(
            'id, name, game_mode, pricing_unit, price, match_minutes, effective_match_seconds, image_url, youtube_url, pricing_tiers',
          )
          .eq('venue_id', venueId)
          .eq('is_available', true)
          .order('name'),
      _client
          .from('sessions')
          .select(
            'id, number, post_id, game_id, customer_id, status, started_at, paused_at, ended_at, '
            'planned_duration_seconds, total_paused_seconds, match_count, '
            'games(name, game_mode, pricing_unit, price, match_minutes, effective_match_seconds, image_url, youtube_url, pricing_tiers), '
            'posts(name), customers(id, full_name)',
          )
          .eq('venue_id', venueId)
          .inFilter('status', [
            'starting',
            'active',
            'paused',
            'waiting_payment',
          ])
          .order('created_at'),
      _client
          .from('session_requests')
          .select(
            'id, session_id, post_id, type, payload, created_at, posts(name), customers(full_name)',
          )
          .eq('venue_id', venueId)
          .eq('status', 'pending')
          .order('created_at'),
      _client
          .from('session_bill')
          .select(
            'session_id, gaming_total, products_total, paid_total, balance_due',
          )
          .eq('venue_id', venueId),
      _client
          .from('products')
          .select('id, name, sale_price, stock_quantity, is_available')
          .eq('venue_id', venueId)
          .eq('is_available', true)
          .order('name'),
      _client
          .from('customers')
          .select('id, full_name')
          .eq('venue_id', venueId)
          .order('full_name'),
      _client
          .from('promotions')
          .select('id, name, discount_percent')
          .eq('venue_id', venueId)
          .eq('is_active', true)
          .lte('starts_at', now)
          .gt('ends_at', now)
          .order('name'),
      _client
          .from('customer_order_requests')
          .select(
            'id, quantity, expected_unit_price, customers(full_name), products(name)',
          )
          .eq('venue_id', venueId)
          .eq('status', 'pending')
          .order('created_at'),
    ]);

    final rawPosts = results[0] as List<dynamic>;
    final rawGames = results[1] as List<dynamic>;
    final rawSessions = results[2] as List<dynamic>;
    final rawRequests = results[3] as List<dynamic>;
    final rawBills = results[4] as List<dynamic>;
    final rawProducts = results[5] as List<dynamic>;
    final rawCustomers = results[6] as List<dynamic>;
    final rawPromotions = results[7] as List<dynamic>;
    final rawStandaloneOrderRequests = results[8] as List<dynamic>;
    final customerIds = rawSessions
        .cast<Map<String, dynamic>>()
        .map((row) => row['customer_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    final customerBalances = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('customer_balances')
                  .select(
                    'customer_id, wallet_balance, credit_balance, credit_limit',
                  )
                  .inFilter('customer_id', customerIds))
              .cast<Map<String, dynamic>>();
    final activeSessionIds = rawSessions
        .cast<Map<String, dynamic>>()
        .map((row) => row['id'] as String)
        .toList(growable: false);
    final redeemedSessionIds = activeSessionIds.isEmpty
        ? <String>{}
        : (await _client
                  .from('promotion_redemptions')
                  .select('session_id')
                  .inFilter('session_id', activeSessionIds))
              .cast<Map<String, dynamic>>()
              .map((row) => row['session_id'] as String)
              .toSet();
    final balancesByCustomer = {
      for (final row in customerBalances) row['customer_id'] as String: row,
    };
    final totalsBySession = {
      for (final row in rawBills.cast<Map<String, dynamic>>())
        row['session_id'] as String: {
          'gaming_total': (row['gaming_total'] as num).toDouble(),
          'products_total': (row['products_total'] as num).toDouble(),
          'paid_total': (row['paid_total'] as num).toDouble(),
          'balance_due': (row['balance_due'] as num).toDouble(),
        },
    };
    return SessionDashboardSnapshot(
      venueId: venueId,
      venueName: venue.name,
      timeZone: venue.timeZone,
      canManageCredit: venue.canManageCredit,
      canGiveDiscount: venue.canGiveDiscount,
      canManagePromotions: venue.canManageCatalog,
      posts: rawPosts
          .map((row) => GamingPost.fromJson(row as Map<String, dynamic>))
          .toList()
            ..sort((a, b) => a.number.compareTo(b.number)),
      games: rawGames
          .map((row) => CatalogGame.fromJson(row as Map<String, dynamic>))
          .toList(),
      customers: rawCustomers
          .map((row) => VenueCustomer.fromJson(row as Map<String, dynamic>))
          .toList(),
      promotions: rawPromotions
          .map((row) => SessionPromotion.fromJson(row as Map<String, dynamic>))
          .toList(),
      sessions: rawSessions.map((row) {
        final data = row as Map<String, dynamic>;
        final customer = data['customers'];
        final balance = customer is Map<String, dynamic>
            ? balancesByCustomer[customer['id'] as String?]
            : null;
        return ActiveGamingSession.fromJson({
          ...data,
          ...?totalsBySession[data['id'] as String],
          ...?balance,
          'promotion_applied': redeemedSessionIds.contains(data['id']),
        }, timeZone: venue.timeZone);
      }).toList(),
      requests: rawRequests
          .map(
            (row) => PendingSessionRequest.fromJson(
              row as Map<String, dynamic>,
              timeZone: venue.timeZone,
            ),
          )
          .toList(),
      standaloneOrderRequests: rawStandaloneOrderRequests
          .map(
            (row) => PendingStandaloneOrderRequest.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList(),
      products: rawProducts
          .map((row) => SessionProduct.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  RealtimeChannel subscribeToVenue(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:sessions',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  RealtimeChannel subscribeToPosts(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:posts',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  RealtimeChannel subscribeToCatalog(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:catalog',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  RealtimeChannel subscribeToRequests(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:requests',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  RealtimeChannel subscribeToInventory(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:inventory',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  RealtimeChannel subscribeToCustomers(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:customers',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  RealtimeChannel subscribeToPromotions(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:promotions',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.onBroadcast(event: event, callback: (_) => onChange());
    }
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onError();
      }
    });
    return channel;
  }

  Future<Map<String, dynamic>> call(
    String rpc,
    Map<String, dynamic> params,
  ) async {
    try {
      final result = await executeIdempotentRpc<Object?>(_client, rpc, {
        'p_op': _newOperationId(),
        ...params,
      });
      return Map<String, dynamic>.from(result as Map);
    } on PostgrestException catch (error) {
      throw SessionDashboardException(_friendlyError(error.message));
    } on AuthException {
      throw const SessionDashboardException(
        'Votre session a expiré. Reconnectez-vous.',
      );
    }
  }

  Future<Map<String, dynamic>> applyPromotion(
    String sessionId,
    String promotionId,
  ) => call('apply_session_promotion', {
    'p_session': sessionId,
    'p_promotion': promotionId,
  });

  Future<List<Map<String, dynamic>>> loadSessionOrderItems(String sessionId) async {
    try {
      final response = await _client
          .from('order_items')
          .select('quantity, unit_price, line_total, products(name), orders!inner(session_id)')
          .eq('orders.session_id', sessionId);
      return (response as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  String _newOperationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  String _friendlyError(String message) {
    const messages = {
      'FORBIDDEN': 'Votre rôle ne permet pas de démarrer ou modifier une session.',
      '42501': 'Votre rôle ne permet pas de démarrer ou modifier une session.',
      'POST_NOT_AVAILABLE': 'Ce poste n’est plus disponible.',
      'POST_NOT_FOUND': 'Ce poste est introuvable.',
      'GAME_NOT_AVAILABLE': 'Ce jeu n’est plus disponible.',
      'GAME_NOT_SUPPORTED_ON_POST': 'Ce jeu n’est pas disponible sur ce poste.',
      'POST_GAME_NOT_SUPPORTED':
          'Ce jeu ne peut pas être transféré vers ce poste.',
      'CUSTOMER_NOT_FOUND': 'Le client est introuvable.',
      'SESSION_NOT_ACTIVE': 'Cette session n’est plus en cours.',
      'SESSION_NOT_PAUSED': 'Cette session n’est pas en pause.',
      'SESSION_NOT_FOUND': 'La session est introuvable.',
      'SAME_POST':
          'Choisissez un poste différent de celui utilisé actuellement.',
      'GAME_NOT_MATCH_BASED': 'Cette session n’est pas basée sur les matchs.',
      'GAME_NOT_TIME_BASED': 'Cette session n’est pas basée sur le temps.',
      'INITIAL_DURATION_REQUIRED': 'Choisissez une durée de session.',
      'INVALID_DURATION': 'La durée choisie est invalide.',
      'INVALID_QUANTITY': 'Le nombre de matchs est invalide.',
      'PRODUCT_NOT_FOUND': 'Ce produit est introuvable.',
      'PRODUCT_NOT_AVAILABLE': 'Ce produit n’est plus disponible.',
      'INSUFFICIENT_STOCK': 'Le stock disponible est insuffisant.',
      'ORDER_REQUEST_NOT_FOUND': 'Cette demande de commande est introuvable.',
      'ORDER_REQUEST_ALREADY_HANDLED':
          'Cette demande a déjà été traitée par un autre employé.',
      'SESSION_NOT_WAITING_PAYMENT':
          'Cette session n’est plus en attente de règlement.',
      'PAYMENT_TOTAL_MISMATCH':
          'Le montant des paiements ne correspond pas au solde dû.',
      'INVALID_PAYMENT_LINES': 'Les modes de paiement sont invalides.',
      'INVALID_PAYMENT_METHOD': 'Le mode de paiement est invalide.',
      'PRODUCT_PRICE_CHANGED':
          'Le prix a changé. Actualisez le catalogue avant de commander.',
      'INVALID_PAYMENT_AMOUNT': 'Le montant du paiement est invalide.',
      'INVALID_PAYMENT_LINE': 'Une ligne de paiement est invalide.',
      'INVALID_FINANCIAL_AMOUNT': 'Le montant doit être valide, en centimes.',
      'INVALID_FINANCIAL_ACTION': 'Cette opération financière est invalide.',
      'INSUFFICIENT_WALLET': 'Le solde du portefeuille est insuffisant.',
      'CREDIT_LIMIT_EXCEEDED': 'La limite de crédit du client serait dépassée.',
      'REPAYMENT_EXCEEDS_BALANCE':
          'Le remboursement dépasse le crédit restant.',
      'CREDIT_LIMIT_BELOW_BALANCE':
          'La limite ne peut pas être inférieure au crédit utilisé.',
      'PROMOTION_NOT_FOUND': 'Cette promotion n’existe plus.',
      'PROMOTION_NOT_ACTIVE': 'Cette promotion n’est pas active actuellement.',
      'PROMOTION_ALREADY_APPLIED':
          'Une promotion a déjà été appliquée à cette session.',
      'PROMOTION_NO_ELIGIBLE_CHARGES':
          'Cette session ne contient aucun montant éligible.',
      'CUSTOMER_REQUIRED':
          'Associez un client à la session pour utiliser son compte.',
      'NEGATIVE_SESSION_BALANCE':
          'Le solde de cette session doit être vérifié avant sa clôture.',
      'REQUEST_NOT_PENDING': 'Cette demande a déjà été traitée.',
      'REQUEST_ALREADY_PENDING': 'Une demande de ce type est déjà en attente.',
      'VENUE_NOT_FOUND': 'Aucune salle n’est associée à votre compte.',
      'UNAUTHENTICATED': 'Votre session a expiré. Reconnectez-vous.',
    };
    final code = message.split(':').first.trim();
    return messages[code] ?? message;
  }
}

class SessionDashboardException implements Exception {
  const SessionDashboardException(this.message);

  final String message;

  @override
  String toString() => message;
}
