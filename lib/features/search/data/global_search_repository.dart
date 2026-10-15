import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';

class GlobalSearchResult {
  const GlobalSearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.section,
    required this.route,
  });

  final String id;
  final String title;
  final String subtitle;
  final String section;
  final String route;
}

class GlobalSearchRepository {
  GlobalSearchRepository(this._client);

  final SupabaseClient _client;

  Future<List<GlobalSearchResult>> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2) return const [];

    final venue = await VenueRepository(_client).currentVenue();
    final role = venue.role;
    final canSearchCredit =
        role == 'owner' ||
        role == 'manager' ||
        (role == 'employee' && venue.permissions['manage_credit'] == true);
    final escapedQuery = query.replaceAll('%', r'\%').replaceAll('_', r'\_');
    final pattern = '%$escapedQuery%';
    final number = int.tryParse(query);
    final uuid = _isUuid(query) ? query : null;

    final requests = <Future<List<GlobalSearchResult>>>[
      _searchRows(
        () => _client
            .from('posts')
            .select('id, name, number, status')
            .eq('venue_id', venue.id)
            .ilike('name', pattern)
            .limit(8),
        (row) => GlobalSearchResult(
          id: row['id'] as String,
          title: row['name'] as String,
          subtitle: 'Poste ${row['number']} · ${_postStatus(row['status'])}',
          section: 'Postes',
          route: role == 'customer' ? '/customer/home' : '/posts',
        ),
      ),
      _searchRows(
        () => _client
            .from('games')
            .select('id, name, platform, price')
            .eq('venue_id', venue.id)
            .ilike('name', pattern)
            .limit(8),
        (row) => GlobalSearchResult(
          id: row['id'] as String,
          title: row['name'] as String,
          subtitle:
              '${row['platform']} · ${(row['price'] as num).toStringAsFixed(0)} DA',
          section: 'Jeux',
          route: role == 'owner' || role == 'manager'
              ? '/games'
              : role == 'customer'
              ? '/customer/home'
              : '/home',
        ),
      ),
      _searchRows(
        () => _client
            .from('products')
            .select('id, name, stock_quantity, sale_price')
            .eq('venue_id', venue.id)
            .ilike('name', pattern)
            .limit(8),
        (row) => GlobalSearchResult(
          id: row['id'] as String,
          title: row['name'] as String,
          subtitle:
              'Stock : ${row['stock_quantity']} · '
              '${(row['sale_price'] as num).toStringAsFixed(0)} DA',
          section: 'Produits',
          route: role == 'customer'
              ? '/customer/home'
              : role == 'employee' && venue.permissions['manage_stock'] != true
              ? '/home'
              : '/inventory',
        ),
      ),
    ];

    if (canSearchCredit) {
      requests.addAll([
        _searchCustomers(pattern, venue.id),
        _searchCreditAccounts(pattern, venue.id),
      ]);
    }

    if (number != null) {
      requests.addAll([
        _searchRows(
          () => _client
              .from('sessions')
              .select('id, number, status, customers(full_name), posts(name)')
              .eq('venue_id', venue.id)
              .eq('number', number)
              .limit(5),
          (row) => GlobalSearchResult(
            id: row['id'] as String,
            title: 'Session #${row['number']}',
            subtitle:
                '${_sessionStatus(row['status'])} · '
                '${_relatedName(row['customers'], 'full_name', 'Client')} · '
                '${_relatedName(row['posts'], 'name', 'Poste')}',
            section: 'Sessions',
            route: role == 'customer'
                ? '/customer/home?sessionId=${Uri.encodeQueryComponent(row['id'] as String)}'
                : '/home?sessionId=${Uri.encodeQueryComponent(row['id'] as String)}',
          ),
        ),
        _searchRows(
          () => _client
              .from('invoices')
              .select('id, number, total')
              .eq('venue_id', venue.id)
              .eq('number', number)
              .limit(5),
          (row) => GlobalSearchResult(
            id: row['id'] as String,
            title: 'Facture #${row['number']}',
            subtitle: '${(row['total'] as num).toStringAsFixed(0)} DA',
            section: 'Factures',
            route: '/invoices',
          ),
        ),
      ]);
    }

    if (uuid != null) {
      requests.add(
        _searchRows(
          () => _client
              .from('orders')
              .select('id, status, total')
              .eq('venue_id', venue.id)
              .eq('id', uuid)
              .limit(1),
          (row) => GlobalSearchResult(
            id: row['id'] as String,
            title: 'Commande ${_orderStatus(row['status'])}',
            subtitle: '${(row['total'] as num).toStringAsFixed(0)} DA',
            section: 'Commandes',
            route: '/invoices',
          ),
        ),
      );
    }

    final groups = await Future.wait(requests);
    return groups.expand((group) => group).toList(growable: false);
  }

  Future<List<GlobalSearchResult>> _searchRows(
    Future<dynamic> Function() request,
    GlobalSearchResult Function(Map<String, dynamic>) map,
  ) async {
    final rows = await request();
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(map)
        .toList(growable: false);
  }

  Future<List<GlobalSearchResult>> _searchCustomers(
    String pattern,
    String venueId,
  ) async {
    final rows =
        (await _client
                .from('customers')
                .select('id, full_name, phone')
                .eq('venue_id', venueId)
                .ilike('full_name', pattern)
                .limit(8))
            .cast<Map<String, dynamic>>();
    return rows
        .map(
          (row) => GlobalSearchResult(
            id: row['id'] as String,
            title: row['full_name'] as String,
            subtitle: row['phone'] as String? ?? 'Client',
            section: 'Clients',
            route: '/customers',
          ),
        )
        .toList(growable: false);
  }

  Future<List<GlobalSearchResult>> _searchCreditAccounts(
    String pattern,
    String venueId,
  ) async {
    final customers =
        (await _client
                .from('customers')
                .select('id, full_name')
                .eq('venue_id', venueId)
                .ilike('full_name', pattern)
                .limit(8))
            .cast<Map<String, dynamic>>();
    if (customers.isEmpty) return const [];
    final balances =
        (await _client
                .from('customer_balances')
                .select('customer_id, credit_balance, credit_limit')
                .eq('venue_id', venueId)
                .inFilter(
                  'customer_id',
                  customers
                      .map((customer) => customer['id'] as String)
                      .toList(),
                ))
            .cast<Map<String, dynamic>>()
            .asMap();
    final balanceByCustomer = {
      for (final row in balances.values) row['customer_id'] as String: row,
    };
    return customers
        .map((customer) {
          final balance = balanceByCustomer[customer['id']];
          if (balance == null) return null;
          return GlobalSearchResult(
            id: customer['id'] as String,
            title: customer['full_name'] as String,
            subtitle:
                'Crédit : ${(balance['credit_balance'] as num).toStringAsFixed(0)}'
                ' / ${(balance['credit_limit'] as num).toStringAsFixed(0)} DA',
            section: 'Crédit',
            route: '/customers',
          );
        })
        .whereType<GlobalSearchResult>()
        .toList(growable: false);
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  String _relatedName(Object? value, String key, String fallback) {
    if (value is Map && value[key] is String) return value[key] as String;
    return fallback;
  }

  String _postStatus(Object? status) => switch (status) {
    'available' => 'Disponible',
    'playing' || 'starting' => 'En cours',
    'paused' => 'En pause',
    'waiting_payment' => 'Paiement en attente',
    'reserved' => 'Réservé',
    _ => 'Indisponible',
  };

  String _sessionStatus(Object? status) => switch (status) {
    'active' => 'En cours',
    'paused' => 'En pause',
    'waiting_payment' => 'Paiement en attente',
    _ => 'Terminée',
  };

  String _orderStatus(Object? status) => switch (status) {
    'paid' => 'payée',
    'added_to_session' => 'associée à une session',
    'cancelled' => 'annulée',
    _ => 'reçue',
  };
}
