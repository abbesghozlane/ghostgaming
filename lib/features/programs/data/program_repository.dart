import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/offline/offline_operation_queue.dart';
import '../../../core/utils/operation_id.dart';

class ProgramRepository {
  ProgramRepository(this._client);

  final SupabaseClient _client;

  Future<ProgramSnapshot> load() async {
    final venue = await VenueRepository(_client).currentVenue();
    final results = await Future.wait([
      _client
          .from('membership_plans')
          .select('id, name, duration_days, benefits, is_active')
          .eq('venue_id', venue.id)
          .order('name'),
      _client
          .from('packages')
          .select(
            'id, name, description, price, gaming_minutes, is_active, '
            'package_items(id, product_id, quantity, products(name, stock_quantity))',
          )
          .eq('venue_id', venue.id)
          .order('price'),
      _client
          .from('customers')
          .select('id, full_name')
          .eq('venue_id', venue.id)
          .order('full_name'),
      _client
          .from('customer_memberships')
          .select(
            'id, customer_id, plan_name, benefits, starts_at, ends_at, '
            'customers(full_name)',
          )
          .eq('venue_id', venue.id)
          .order('ends_at', ascending: false)
          .limit(100),
      _client
          .from('package_purchases')
          .select(
            'id, customer_id, package_name, gaming_minutes_remaining, expires_at, created_at, '
            'customers(full_name), package_purchase_items('
            'id, product_name, purchased_quantity, remaining_quantity)',
          )
          .eq('venue_id', venue.id)
          .order('created_at', ascending: false)
          .limit(100),
      _client
          .from('products')
          .select('id, name, stock_quantity, is_available')
          .eq('venue_id', venue.id)
          .eq('is_available', true)
          .order('name'),
    ]);
    return ProgramSnapshot(
      venue: venue,
      membershipPlans: _rows(results[0]),
      packages: _rows(results[1]),
      customers: _rows(results[2]),
      memberships: _rows(results[3]),
      purchases: _rows(results[4]),
      products: _rows(results[5]),
    );
  }

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List).cast<Map<String, dynamic>>();

  Future<void> saveMembershipPlan({
    String? planId,
    required String venueId,
    required String name,
    required int durationDays,
    required String benefits,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 100 ||
        durationDays < 1 ||
        durationDays > 3650 ||
        benefits.length > 2000) {
      throw const ProgramException('INVALID_MEMBERSHIP_PLAN');
    }
    final values = {
      'name': cleanName,
      'duration_days': durationDays,
      'benefits': benefits.trim(),
    };
    if (planId == null) {
      await _client.from('membership_plans').insert({
        ...values,
        'venue_id': venueId,
      });
      return;
    }
    final updated = await _client
        .from('membership_plans')
        .update(values)
        .eq('id', planId)
        .eq('venue_id', venueId)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw const ProgramException('MEMBERSHIP_PLAN_NOT_FOUND');
    }
  }

  Future<void> setMembershipPlanActive(String id, bool active) async {
    final updated = await _client
        .from('membership_plans')
        .update({'is_active': active})
        .eq('id', id)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw const ProgramException('MEMBERSHIP_PLAN_NOT_FOUND');
    }
  }

  Future<void> savePackage({
    String? packageId,
    required String name,
    required String description,
    required double price,
    required int gamingMinutes,
    required List<Map<String, dynamic>> items,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 100 ||
        !price.isFinite ||
        price <= 0 ||
        gamingMinutes < 1 ||
        gamingMinutes > 100000 ||
        description.length > 2000 ||
        items.isEmpty ||
        items.any(
          (item) =>
              (item['quantity'] as int? ?? 0) < 1 ||
              (item['quantity'] as int? ?? 0) > 100,
        ) ||
        items.map((item) => item['product_id']).toSet().length !=
            items.length) {
      throw const ProgramException('INVALID_PACKAGE');
    }
    await executeIdempotentRpc<void>(_client, 'save_program_package', {
      'p_op': OperationId.create(),
      'p_package': packageId,
      'p_name': cleanName,
      'p_description': description.trim(),
      'p_price': price,
      'p_gaming_minutes': gamingMinutes,
      'p_items': items,
    });
  }

  Future<void> setPackageActive(String id, bool active) async {
    final updated = await _client
        .from('packages')
        .update({'is_active': active})
        .eq('id', id)
        .select('id')
        .maybeSingle();
    if (updated == null) throw const ProgramException('PACKAGE_NOT_FOUND');
  }

  Future<void> assignMembership({
    required String customerId,
    required String planId,
  }) async {
    await executeIdempotentRpc<void>(_client, 'assign_customer_membership', {
      'p_op': OperationId.create(),
      'p_customer': customerId,
      'p_plan': planId,
    });
  }

  Future<void> sellPackage({
    required String customerId,
    required String packageId,
    required String method,
  }) async {
    await executeIdempotentRpc<void>(_client, 'sell_customer_package', {
      'p_op': OperationId.create(),
      'p_customer': customerId,
      'p_package': packageId,
      'p_method': method,
    });
  }

  Future<void> redeemProduct({
    required String purchaseItemId,
    required int quantity,
  }) async {
    await executeIdempotentRpc<void>(_client, 'redeem_package_product', {
      'p_op': OperationId.create(),
      'p_purchase_item': purchaseItemId,
      'p_quantity': quantity,
    });
  }

  RealtimeChannel subscribe(
    String venueId, {
    required void Function() onChange,
    required void Function() onError,
  }) {
    final channel = _client.channel(
      'venue:$venueId:programs',
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
}

class ProgramSnapshot {
  const ProgramSnapshot({
    required this.venue,
    required this.membershipPlans,
    required this.packages,
    required this.customers,
    required this.memberships,
    required this.purchases,
    required this.products,
  });

  final VenueContext venue;
  final List<Map<String, dynamic>> membershipPlans;
  final List<Map<String, dynamic>> packages;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> memberships;
  final List<Map<String, dynamic>> purchases;
  final List<Map<String, dynamic>> products;
}

class ProgramException implements Exception {
  const ProgramException(this.code);

  final String code;
}
