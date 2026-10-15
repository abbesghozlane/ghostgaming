import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/venue_repository.dart';
import '../../../core/utils/venue_time_zone.dart';

enum ReportPeriod {
  today('Aujourd’hui'),
  yesterday('Hier'),
  thisWeek('Cette semaine'),
  thisMonth('Ce mois');

  const ReportPeriod(this.label);

  final String label;

  ReportDateRange dateRange(
    DateTime now, {
    String timeZone = 'Africa/Algiers',
  }) {
    final venueNow = VenueTimeZone.now(timeZone, instant: now);
    final today = VenueTimeZone.dateTime(
      timeZone,
      year: venueNow.year,
      month: venueNow.month,
      day: venueNow.day,
    );
    final weekStart = VenueTimeZone.dateTime(
      timeZone,
      year: venueNow.year,
      month: venueNow.month,
      day: venueNow.day - venueNow.weekday + 1,
    );
    return switch (this) {
      ReportPeriod.today => ReportDateRange(
        start: today,
        end: VenueTimeZone.dateTime(
          timeZone,
          year: venueNow.year,
          month: venueNow.month,
          day: venueNow.day + 1,
        ),
        timeZone: timeZone,
      ),
      ReportPeriod.yesterday => ReportDateRange(
        start: VenueTimeZone.dateTime(
          timeZone,
          year: venueNow.year,
          month: venueNow.month,
          day: venueNow.day - 1,
        ),
        end: today,
        timeZone: timeZone,
      ),
      ReportPeriod.thisWeek => ReportDateRange(
        start: weekStart,
        end: VenueTimeZone.dateTime(
          timeZone,
          year: weekStart.year,
          month: weekStart.month,
          day: weekStart.day + 7,
        ),
        timeZone: timeZone,
      ),
      ReportPeriod.thisMonth => ReportDateRange(
        start: VenueTimeZone.dateTime(
          timeZone,
          year: venueNow.year,
          month: venueNow.month,
        ),
        end: VenueTimeZone.dateTime(
          timeZone,
          year: venueNow.year,
          month: venueNow.month + 1,
        ),
        timeZone: timeZone,
      ),
    };
  }
}

class ReportDateRange {
  const ReportDateRange({
    required this.start,
    required this.end,
    this.timeZone = 'Africa/Algiers',
  });

  final DateTime start;
  final DateTime end;
  final String timeZone;
}

class GameRevenue {
  const GameRevenue({
    required this.name,
    required this.revenue,
    required this.matchCount,
    required this.durationSeconds,
  });

  final String name;
  final double revenue;
  final int matchCount;
  final int durationSeconds;
}

class ProductSales {
  const ProductSales({
    required this.name,
    required this.quantity,
    required this.revenue,
  });

  final String name;
  final int quantity;
  final double revenue;
}

class RevenueBucket {
  RevenueBucket({required this.start, required this.label});

  final DateTime start;
  final String label;
  double revenue = 0;
}

class ReportsSnapshot {
  const ReportsSnapshot({
    required this.revenue,
    required this.matchCount,
    required this.productRevenue,
    required this.productUnits,
    required this.gamingDurationSeconds,
    required this.postCount,
    required this.periodDurationSeconds,
    required this.gameRevenue,
    required this.topProducts,
    required this.revenueBuckets,
  });

  final double revenue;
  final int matchCount;
  final double productRevenue;
  final int productUnits;
  final int gamingDurationSeconds;
  final int postCount;
  final int periodDurationSeconds;
  final List<GameRevenue> gameRevenue;
  final List<ProductSales> topProducts;
  final List<RevenueBucket> revenueBuckets;

  double get occupancyRate {
    final availableSeconds = postCount * periodDurationSeconds;
    if (availableSeconds == 0) return 0;
    return (gamingDurationSeconds / availableSeconds).clamp(0, 1);
  }
}

class ReportsRepository {
  ReportsRepository(this._client);

  final SupabaseClient _client;

  Future<ReportsSnapshot> load(ReportPeriod period, {DateTime? now}) async {
    final venue = await VenueRepository(_client).currentVenue();
    final range = period.dateRange(
      now ?? DateTime.now(),
      timeZone: venue.timeZone,
    );
    final startUtc = range.start.toUtc().toIso8601String();
    final endUtc = range.end.toUtc().toIso8601String();
    final results = await Future.wait([
      _client
          .from('sessions')
          .select(
            'id, game_id, match_count, started_at, ended_at, '
            'total_paused_seconds, games(name)',
          )
          .eq('venue_id', venue.id)
          .eq('status', 'closed')
          .gte('started_at', startUtc)
          .lt('started_at', endUtc),
      _client
          .from('orders')
          .select('id, total, created_at')
          .eq('venue_id', venue.id)
          .eq('status', 'paid')
          .gte('created_at', startUtc)
          .lt('created_at', endUtc),
      _client.from('posts').select('status').eq('venue_id', venue.id),
    ]);

    final sessions = (results[0] as List<dynamic>).cast<Map<String, dynamic>>();
    final paidOrders = (results[1] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final sessionIds = sessions
        .map((session) => session['id'] as String)
        .toList();
    final attachedOrders = sessionIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('orders')
                  .select('id')
                  .eq('venue_id', venue.id)
                  .eq('status', 'added_to_session')
                  .inFilter('session_id', sessionIds))
              .cast<Map<String, dynamic>>();

    final bills = sessionIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('session_bill')
                  .select('session_id, gaming_total, products_total')
                  .eq('venue_id', venue.id)
                  .inFilter('session_id', sessionIds))
              .cast<Map<String, dynamic>>();
    final orderIds = [
      ...paidOrders.map((order) => order['id'] as String),
      ...attachedOrders.map((order) => order['id'] as String),
    ];
    final rawItems = orderIds.isEmpty
        ? <Map<String, dynamic>>[]
        : (await _client
                  .from('order_items')
                  .select('quantity, line_total, products(name)')
                  .eq('venue_id', venue.id)
                  .inFilter('order_id', orderIds))
              .cast<Map<String, dynamic>>();

    final billsBySession = {
      for (final bill in bills) bill['session_id'] as String: bill,
    };
    final buckets = _createBuckets(range);
    final revenueByGame = <String, _MutableGameRevenue>{};
    var revenue = 0.0;
    var matchCount = 0;
    var gamingDurationSeconds = 0;

    for (final session in sessions) {
      final sessionId = session['id'] as String;
      final bill = billsBySession[sessionId];
      final gamingTotal = _number(bill?['gaming_total']);
      final productsTotal = _number(bill?['products_total']);
      final sessionRevenue = gamingTotal + productsTotal;
      final gameId = session['game_id'] as String;
      final rawGame = session['games'] as Map<String, dynamic>?;
      final gameName = rawGame?['name'] as String? ?? 'Jeu supprimé';
      final matches = _integer(session['match_count']);
      final durationSeconds = _sessionDurationSeconds(session, range.timeZone);

      revenue += sessionRevenue;
      matchCount += matches;
      gamingDurationSeconds += durationSeconds;
      final game = revenueByGame.putIfAbsent(
        gameId,
        () => _MutableGameRevenue(gameName),
      );
      game
        ..revenue += sessionRevenue
        ..matchCount += matches
        ..durationSeconds += durationSeconds;
      _addToBucket(
        buckets,
        range,
        VenueTimeZone.parse(session['started_at'] as String?, range.timeZone)!,
        sessionRevenue,
      );
    }

    for (final order in paidOrders) {
      final orderRevenue = _number(order['total']);
      revenue += orderRevenue;
      _addToBucket(
        buckets,
        range,
        VenueTimeZone.parse(order['created_at'] as String?, range.timeZone)!,
        orderRevenue,
      );
    }

    final productSales = <String, _MutableProductSales>{};
    var productUnits = 0;
    var productRevenue = 0.0;
    for (final item in rawItems) {
      final quantity = _integer(item['quantity']);
      final lineTotal = _number(item['line_total']);
      final product = item['products'] as Map<String, dynamic>?;
      final name = product?['name'] as String? ?? 'Produit supprimé';
      productUnits += quantity;
      productRevenue += lineTotal;
      final sales = productSales.putIfAbsent(
        name,
        () => _MutableProductSales(name),
      );
      sales
        ..quantity += quantity
        ..revenue += lineTotal;
    }

    final games = revenueByGame.values.map((game) => game.toModel()).toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final topProducts =
        productSales.values.map((sales) => sales.toModel()).toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));

    final posts = (results[2] as List<dynamic>).cast<Map<String, dynamic>>();
    final operationalPostCount = posts
        .where(
          (post) =>
              post['status'] != 'maintenance' && post['status'] != 'offline',
        )
        .length;

    return ReportsSnapshot(
      revenue: revenue,
      matchCount: matchCount,
      productRevenue: productRevenue,
      productUnits: productUnits,
      gamingDurationSeconds: gamingDurationSeconds,
      postCount: operationalPostCount,
      periodDurationSeconds: range.end.difference(range.start).inSeconds,
      gameRevenue: games,
      topProducts: topProducts,
      revenueBuckets: buckets,
    );
  }

  List<RevenueBucket> _createBuckets(ReportDateRange range) {
    final isSingleDay = range.end.difference(range.start).inDays <= 1;
    if (isSingleDay) {
      return List.generate(
        24,
        (hour) => RevenueBucket(
          start: VenueTimeZone.dateTime(
            range.timeZone,
            year: range.start.year,
            month: range.start.month,
            day: range.start.day,
            hour: hour,
          ),
          label: '${hour.toString().padLeft(2, '0')}h',
        ),
      );
    }

    final buckets = <RevenueBucket>[];
    for (
      var day = VenueTimeZone.dateTime(
        range.timeZone,
        year: range.start.year,
        month: range.start.month,
        day: range.start.day,
      );
      day.isBefore(range.end);
      day = VenueTimeZone.dateTime(
        range.timeZone,
        year: day.year,
        month: day.month,
        day: day.day + 1,
      )
    ) {
      buckets.add(
        RevenueBucket(
          start: day,
          label:
              '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
        ),
      );
    }
    return buckets;
  }

  void _addToBucket(
    List<RevenueBucket> buckets,
    ReportDateRange range,
    DateTime date,
    double amount,
  ) {
    final venueDate = VenueTimeZone.parse(
      date.toIso8601String(),
      range.timeZone,
    )!;
    final isSingleDay = range.end.difference(range.start).inDays <= 1;
    final index = isSingleDay
        ? venueDate.hour
        : DateTime.utc(venueDate.year, venueDate.month, venueDate.day)
              .difference(
                DateTime.utc(
                  range.start.year,
                  range.start.month,
                  range.start.day,
                ),
              )
              .inDays;
    if (index >= 0 && index < buckets.length) {
      buckets[index].revenue += amount;
    }
  }

  int _sessionDurationSeconds(Map<String, dynamic> session, String timeZone) {
    final startedAt = VenueTimeZone.parse(
      session['started_at'] as String?,
      timeZone,
    );
    final endedAt = VenueTimeZone.parse(
      session['ended_at'] as String?,
      timeZone,
    );
    if (startedAt == null || endedAt == null) return 0;
    final elapsed = endedAt.difference(startedAt).inSeconds;
    return (elapsed - _integer(session['total_paused_seconds'])).clamp(
      0,
      elapsed,
    );
  }

  double _number(Object? value) => value is num ? value.toDouble() : 0;

  int _integer(Object? value) => value is num ? value.toInt() : 0;
}

class _MutableGameRevenue {
  _MutableGameRevenue(this.name);

  final String name;
  double revenue = 0;
  int matchCount = 0;
  int durationSeconds = 0;

  GameRevenue toModel() => GameRevenue(
    name: name,
    revenue: revenue,
    matchCount: matchCount,
    durationSeconds: durationSeconds,
  );
}

class _MutableProductSales {
  _MutableProductSales(this.name);

  final String name;
  int quantity = 0;
  double revenue = 0;

  ProductSales toModel() =>
      ProductSales(name: name, quantity: quantity, revenue: revenue);
}
