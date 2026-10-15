import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';

class CustomerRepository {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  Future<void> requestPhoneCode({
    required String phone,
    required String fullName,
  }) async {
    await _client.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: true,
      data: {'full_name': fullName},
    );
  }

  Future<void> verifyPhoneCode({
    required String phone,
    required String code,
    required String fullName,
  }) async {
    final response = await _client.auth.verifyOTP(
      phone: phone,
      token: code,
      type: OtpType.sms,
    );
    if (response.session == null || response.user?.phoneConfirmedAt == null) {
      throw const CustomerFlowException(
        'Le numéro n’a pas pu être vérifié. Vérifiez le code reçu.',
      );
    }
    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName.trim()}),
    );
  }

  Future<Map<String, dynamic>> linkToPost(String qrToken) async {
    final response = await _client.rpc(
      'link_customer_to_post',
      params: {'p_qr_token': qrToken},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<CustomerHomeSnapshot> loadHome() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const CustomerFlowException(
        'Connectez-vous pour accéder à votre espace.',
      );
    }

    final customers =
        (await _client
                .from('customers')
                .select('id, venue_id, full_name, venues(name, timezone)')
                .eq('user_id', user.id))
            .cast<Map<String, dynamic>>();
    final customerIds = customers.map((row) => row['id'] as String).toList();
    final standaloneOrderRequests = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('customer_order_requests')
                  .select(
                    'id, venue_id, quantity, expected_unit_price, status, created_at, '
                    'products(name), orders(id, session_id)',
                  )
                  .inFilter('customer_id', customerIds)
                  .order('created_at', ascending: false)
                  .limit(10))
              .cast<Map<String, dynamic>>();
    final balances = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('customer_balances')
                  .select(
                    'customer_id, wallet_balance, credit_balance, credit_limit',
                  )
                  .inFilter('customer_id', customerIds))
              .cast<Map<String, dynamic>>();
    final loyaltyBalances = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('loyalty_balances')
                  .select('customer_id, points_balance')
                  .inFilter('customer_id', customerIds))
              .cast<Map<String, dynamic>>();
    final ledgerEntries = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('customer_ledger_entries')
                  .select('id, customer_id, account, delta, reason, created_at')
                  .inFilter('customer_id', customerIds)
                  .order('created_at', ascending: false)
                  .limit(10))
              .cast<Map<String, dynamic>>();
    final sessions = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('sessions')
                  .select(
                    'id, venue_id, status, match_count, started_at, paused_at, '
                    'ended_at, total_paused_seconds, planned_duration_seconds, '
                    'games(name, game_mode, image_url), posts(name)',
                  )
                  .inFilter('customer_id', customerIds)
                  .inFilter('status', [
                    'starting',
                    'active',
                    'paused',
                    'waiting_payment',
                  ])
                  .order('created_at', ascending: false))
              .cast<Map<String, dynamic>>();
    final sessionIds = sessions.map((row) => row['id'] as String).toList();
    final bills = sessionIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('session_bill')
                  .select(
                    'session_id, gaming_total, products_total, paid_total, balance_due',
                  )
                  .inFilter('session_id', sessionIds))
              .cast<Map<String, dynamic>>();
    final requests = sessionIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('session_requests')
                  .select('id, session_id, type, status, payload, created_at')
                  .inFilter('session_id', sessionIds)
                  .order('created_at', ascending: false))
              .cast<Map<String, dynamic>>();
    final venueIds = customers
        .map((row) => row['venue_id'] as String)
        .toSet()
        .toList();
    final loyaltyRewards = venueIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('loyalty_rewards')
                  .select(
                    'id, venue_id, name, description, points_cost, stock_quantity',
                  )
                  .inFilter('venue_id', venueIds)
                  .eq('is_active', true)
                  .order('points_cost'))
              .cast<Map<String, dynamic>>();
    final loyaltyRedemptions = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('loyalty_redemptions')
                  .select(
                    'id, customer_id, status, points_cost, note, created_at, '
                    'loyalty_rewards(name)',
                  )
                  .inFilter('customer_id', customerIds)
                  .order('created_at', ascending: false)
                  .limit(10))
              .cast<Map<String, dynamic>>();
    final memberships = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('customer_memberships')
                  .select(
                    'id, venue_id, customer_id, plan_name, benefits, starts_at, ends_at',
                  )
                  .inFilter('customer_id', customerIds)
                  .order('ends_at', ascending: false)
                  .limit(10))
              .cast<Map<String, dynamic>>();
    final packagePurchases = customerIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('package_purchases')
                  .select(
                    'id, venue_id, customer_id, package_name, gaming_minutes_remaining, '
                    'expires_at, '
                    'created_at, package_purchase_items('
                    'id, product_name, purchased_quantity, remaining_quantity)',
                  )
                  .inFilter('customer_id', customerIds)
                  .order('created_at', ascending: false)
                  .limit(20))
              .cast<Map<String, dynamic>>();
    final membershipPlans = venueIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('membership_plans')
                  .select('id, venue_id, name, duration_days, benefits')
                  .inFilter('venue_id', venueIds)
                  .eq('is_active', true)
                  .order('name'))
              .cast<Map<String, dynamic>>();
    final packages = venueIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('packages')
                  .select(
                    'id, venue_id, name, description, price, gaming_minutes, '
                    'package_items(quantity, products(name))',
                  )
                  .inFilter('venue_id', venueIds)
                  .eq('is_active', true)
                  .order('price'))
              .cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> games;
    if (venueIds.isEmpty) {
      games = <Map<String, dynamic>>[];
    } else {
      try {
        games = (await _client
                .from('games')
                .select('id, venue_id, name, subtitle, platform, category, image_url, youtube_url, price, game_mode')
                .inFilter('venue_id', venueIds)
                .eq('is_available', true)
                .order('name'))
            .cast<Map<String, dynamic>>();
      } catch (_) {
        games = (await _client
                .from('games')
                .select('id, venue_id, name, subtitle, platform, category, image_url, price, game_mode')
                .inFilter('venue_id', venueIds)
                .eq('is_available', true)
                .order('name'))
            .cast<Map<String, dynamic>>();
      }
    }
    final products = venueIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('products')
                  .select('id, venue_id, name, sale_price, stock_quantity')
                  .inFilter('venue_id', venueIds)
                  .eq('is_available', true)
                  .order('name'))
              .cast<Map<String, dynamic>>();

    final timeZonesByVenue = <String, String>{
      for (final customer in customers)
        customer['venue_id'] as String:
            ((customer['venues'] as Map<String, dynamic>?)?['timezone']
                as String?) ??
            'Africa/Algiers',
    };
    return CustomerHomeSnapshot(
      timeZonesByVenue: timeZonesByVenue,
      customers: customers,
      balances: balances,
      loyaltyBalances: loyaltyBalances,
      ledgerEntries: ledgerEntries,
      sessions: sessions,
      standaloneOrderRequests: standaloneOrderRequests,
      bills: bills,
      requests: requests,
      games: games,
      products: products,
      loyaltyRewards: loyaltyRewards,
      loyaltyRedemptions: loyaltyRedemptions,
      memberships: memberships,
      packagePurchases: packagePurchases,
      membershipPlans: membershipPlans,
      packages: packages,
    );
  }

  Future<void> createSessionRequest({
    required String sessionId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    await executeIdempotentRpc<void>(_client, 'create_request', {
      'p_op': OperationId.create(),
      'p_session': sessionId,
      'p_type': type,
      'p_payload': payload,
    });
  }

  Future<void> enqueuePostRequest({
    required String postId,
    String? gameId,
    int requestedMinutes = 30,
  }) async {
    await executeIdempotentRpc<void>(_client, 'request_start_session', {
      'p_op': OperationId.create(),
      'p_post': postId,
      'p_game': gameId,
      'p_minutes': requestedMinutes,
    });
  }

  Future<void> addProductToSession({
    required String sessionId,
    required String productId,
    required int quantity,
    required double expectedUnitPrice,
  }) async {
    await executeIdempotentRpc<void>(
      _client,
      'customer_add_product_to_session',
      {
        'p_op': OperationId.create(),
        'p_session': sessionId,
        'p_product': productId,
        'p_quantity': quantity,
        'p_expected_price': expectedUnitPrice,
      },
    );
  }

  Future<void> requestStandaloneProductOrder({
    required String productId,
    required int quantity,
    required double expectedUnitPrice,
    String paymentMethod = 'cash',
  }) async {
    try {
      await executeIdempotentRpc<void>(
        _client,
        'request_standalone_product_order',
        {
          'p_op': OperationId.create(),
          'p_product': productId,
          'p_quantity': quantity,
          'p_expected_price': expectedUnitPrice,
          'p_method': paymentMethod,
        },
      );
    } on PostgrestException catch (e) {
      if (e.message.contains('p_method') ||
          e.message.contains('schema cache') ||
          e.code == 'PGRST202') {
        // Fallback for legacy 4-parameter SQL function on older database schemas
        await executeIdempotentRpc<void>(
          _client,
          'request_standalone_product_order',
          {
            'p_op': OperationId.create(),
            'p_product': productId,
            'p_quantity': quantity,
            'p_expected_price': expectedUnitPrice,
          },
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> attachPreSessionOrder({
    required String requestId,
    required String sessionId,
  }) async {
    await executeIdempotentRpc<void>(_client, 'attach_pre_session_order', {
      'p_op': OperationId.create(),
      'p_request': requestId,
      'p_session': sessionId,
    });
  }

  Future<void> redeemLoyaltyReward({
    required String customerId,
    required String rewardId,
  }) async {
    await executeIdempotentRpc<void>(_client, 'redeem_loyalty_reward', {
      'p_op': OperationId.create(),
      'p_customer': customerId,
      'p_reward': rewardId,
    });
  }

  Future<void> redeemPackageMinutes({
    required String purchaseId,
    required String sessionId,
    required int minutes,
  }) async {
    await executeIdempotentRpc<void>(_client, 'redeem_package_minutes', {
      'p_op': OperationId.create(),
      'p_purchase': purchaseId,
      'p_session': sessionId,
      'p_minutes': minutes,
    });
  }
}

class CustomerHomeSnapshot {
  const CustomerHomeSnapshot({
    required this.timeZonesByVenue,
    required this.customers,
    required this.balances,
    required this.loyaltyBalances,
    required this.ledgerEntries,
    required this.sessions,
    required this.standaloneOrderRequests,
    required this.bills,
    required this.requests,
    required this.games,
    required this.products,
    required this.loyaltyRewards,
    required this.loyaltyRedemptions,
    required this.memberships,
    required this.packagePurchases,
    required this.membershipPlans,
    required this.packages,
  });

  final Map<String, String> timeZonesByVenue;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> balances;
  final List<Map<String, dynamic>> loyaltyBalances;
  final List<Map<String, dynamic>> ledgerEntries;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> standaloneOrderRequests;
  final List<Map<String, dynamic>> bills;
  final List<Map<String, dynamic>> requests;
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> loyaltyRewards;
  final List<Map<String, dynamic>> loyaltyRedemptions;
  final List<Map<String, dynamic>> memberships;
  final List<Map<String, dynamic>> packagePurchases;
  final List<Map<String, dynamic>> membershipPlans;
  final List<Map<String, dynamic>> packages;
}

class CustomerFlowException implements Exception {
  const CustomerFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
