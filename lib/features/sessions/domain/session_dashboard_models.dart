import '../../../core/utils/venue_time_zone.dart';

class GamingPost {
  const GamingPost({
    required this.id,
    required this.name,
    required this.number,
    required this.device,
    required this.status,
    this.maxPlayers = 2,
    this.youtubeUrl,
    this.supportedGameIds = const {},
    this.priceOverrides = const {},
  });

  final String id;
  final String name;
  final int number;
  final String device;
  final String status;
  final int maxPlayers;
  final String? youtubeUrl;
  final Set<String> supportedGameIds;
  final Map<String, double> priceOverrides;

  factory GamingPost.fromJson(Map<String, dynamic> json) => GamingPost(
    id: json['id'] as String,
    name: json['name'] as String,
    number: (json['number'] as num).toInt(),
    device: json['device'] as String? ?? 'other',
    status: json['status'] as String? ?? 'available',
    maxPlayers: (json['max_players'] as num?)?.toInt() ?? 2,
    youtubeUrl: json['youtube_url'] as String?,
    supportedGameIds: (json['post_games'] as List? ?? const [])
        .whereType<Map>()
        .map((link) => link['game_id'] as String)
        .toSet(),
    priceOverrides: {
      for (final override
          in (json['post_game_prices'] as List? ?? const []).whereType<Map>())
        override['game_id'] as String: (override['price_override'] as num)
            .toDouble(),
    },
  );

  bool supportsGame(String gameId) =>
      supportedGameIds.isEmpty || supportedGameIds.contains(gameId);

  double priceFor(CatalogGame game) => priceOverrides[game.id] ?? game.price;
}

List<GamingPost> transferablePosts(
  List<GamingPost> posts,
  ActiveGamingSession session,
) => posts
    .where(
      (post) =>
          post.id != session.postId &&
          post.supportsGame(session.gameId) &&
          (post.status == 'available' || post.status == 'reserved'),
    )
    .toList(growable: false);

List<GamingPost> startablePosts(
  List<GamingPost> posts,
  List<CatalogGame> games,
) => posts
    .where(
      (post) =>
          (post.status == 'available' || post.status == 'reserved') &&
          games.any(
            (game) =>
                (game.mode == 'match_based' ||
                    game.pricingUnit != 'per_match') &&
                post.supportsGame(game.id),
          ),
    )
    .toList(growable: false);

class CatalogGame {
  const CatalogGame({
    required this.id,
    required this.name,
    required this.mode,
    required this.pricingUnit,
    required this.price,
    this.matchMinutes,
    this.effectiveMatchSeconds,
    this.pricingTiers = const {},
    this.imageUrl,
    this.youtubeUrl,
  });

  final String id;
  final String name;
  final String mode;
  final String pricingUnit;
  final double price;
  final int? matchMinutes;
  final int? effectiveMatchSeconds;
  final Map<String, double> pricingTiers;
  final String? imageUrl;
  final String? youtubeUrl;

  factory CatalogGame.fromJson(Map<String, dynamic> json) {
    final rawTiers = json['pricing_tiers'] as Map? ?? const {};
    final tiers = <String, double>{};
    for (final entry in rawTiers.entries) {
      final val = (entry.value as num?)?.toDouble();
      if (val != null) {
        tiers[entry.key.toString()] = val;
      }
    }
    return CatalogGame(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: json['game_mode'] as String? ?? 'time_based',
      pricingUnit: json['pricing_unit'] as String? ?? 'per_hour',
      price: (json['price'] as num).toDouble(),
      matchMinutes: (json['match_minutes'] as num?)?.toInt(),
      effectiveMatchSeconds: (json['effective_match_seconds'] as num?)?.toInt(),
      pricingTiers: tiers,
      imageUrl: json['image_url'] as String?,
      youtubeUrl: json['youtube_url'] as String?,
    );
  }
}

class VenueCustomer {
  const VenueCustomer({required this.id, required this.name});

  final String id;
  final String name;

  factory VenueCustomer.fromJson(Map<String, dynamic> json) => VenueCustomer(
    id: json['id'] as String,
    name: json['full_name'] as String? ?? 'Client',
  );
}

class SessionPromotion {
  const SessionPromotion({
    required this.id,
    required this.name,
    required this.discountPercent,
  });

  final String id;
  final String name;
  final double discountPercent;

  factory SessionPromotion.fromJson(Map<String, dynamic> json) =>
      SessionPromotion(
        id: json['id'] as String,
        name: json['name'] as String,
        discountPercent: (json['discount_percent'] as num).toDouble(),
      );
}

class SessionProduct {
  const SessionProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.stockQuantity,
    required this.isAvailable,
  });

  final String id;
  final String name;
  final double price;
  final int stockQuantity;
  final bool isAvailable;

  factory SessionProduct.fromJson(Map<String, dynamic> json) => SessionProduct(
    id: json['id'] as String,
    name: json['name'] as String,
    price: (json['sale_price'] as num).toDouble(),
    stockQuantity: (json['stock_quantity'] as num).toInt(),
    isAvailable: json['is_available'] as bool? ?? false,
  );
}

class ActiveGamingSession {
  const ActiveGamingSession({
    required this.id,
    this.venueId = '',
    required this.number,
    required this.postId,
    required this.gameId,
    this.customerId,
    required this.status,
    required this.startedAt,
    required this.plannedDurationSeconds,
    required this.totalPausedSeconds,
    required this.matchCount,
    required this.game,
    required this.postName,
    required this.customerName,
    this.pausedAt,
    this.endedAt,
    this.gamingTotal = 0,
    this.productsTotal = 0,
    this.paidTotal = 0,
    this.balanceDue = 0,
    this.walletBalance = 0,
    this.creditBalance = 0,
    this.creditLimit = 0,
    this.promotionApplied = false,
  });

  final String id;
  final String venueId;
  final int number;
  final String postId;
  final String gameId;
  final String? customerId;
  final String status;
  final DateTime? startedAt;
  final DateTime? pausedAt;
  final DateTime? endedAt;
  final int plannedDurationSeconds;
  final int totalPausedSeconds;
  final int matchCount;
  final CatalogGame? game;
  final String? postName;
  final String? customerName;
  final double gamingTotal;
  final double productsTotal;
  final double paidTotal;
  final double balanceDue;
  final double walletBalance;
  final double creditBalance;
  final double creditLimit;
  final bool promotionApplied;
  double get availableCredit => creditLimit - creditBalance;

  factory ActiveGamingSession.fromJson(
    Map<String, dynamic> json, {
    String timeZone = 'Africa/Algiers',
  }) {
    final rawGame = json['games'];
    final rawPost = json['posts'];
    final rawCustomer = json['customers'];
    return ActiveGamingSession(
      id: json['id'] as String,
      venueId: json['venue_id'] as String? ?? '',
      number: (json['number'] as num).toInt(),
      postId: json['post_id'] as String,
      gameId: json['game_id'] as String,
      customerId: json['customer_id'] as String?,
      status: json['status'] as String,
      startedAt: _date(json['started_at'], timeZone),
      pausedAt: _date(json['paused_at'], timeZone),
      endedAt: _date(json['ended_at'], timeZone),
      plannedDurationSeconds:
          (json['planned_duration_seconds'] as num?)?.toInt() ?? 0,
      totalPausedSeconds: (json['total_paused_seconds'] as num?)?.toInt() ?? 0,
      matchCount: (json['match_count'] as num?)?.toInt() ?? 0,
      game: rawGame is Map<String, dynamic>
          ? CatalogGame.fromJson({...rawGame, 'id': json['game_id']})
          : null,
      postName: rawPost is Map<String, dynamic>
          ? rawPost['name'] as String?
          : null,
      customerName: rawCustomer is Map<String, dynamic>
          ? rawCustomer['full_name'] as String?
          : null,
      gamingTotal: (json['gaming_total'] as num?)?.toDouble() ?? 0,
      productsTotal: (json['products_total'] as num?)?.toDouble() ?? 0,
      paidTotal: (json['paid_total'] as num?)?.toDouble() ?? 0,
      balanceDue: (json['balance_due'] as num?)?.toDouble() ?? 0,
      walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0,
      creditBalance: (json['credit_balance'] as num?)?.toDouble() ?? 0,
      creditLimit: (json['credit_limit'] as num?)?.toDouble() ?? 0,
      promotionApplied: json['promotion_applied'] as bool? ?? false,
    );
  }

  int remainingSeconds(DateTime now) {
    final start = startedAt;
    if (start == null) return plannedDurationSeconds;
    final stopAt = status == 'paused' && pausedAt != null
        ? pausedAt!
        : endedAt ?? now;
    final elapsed = stopAt.difference(start).inSeconds - totalPausedSeconds;
    final remaining = plannedDurationSeconds - elapsed;
    return remaining < 0 ? 0 : remaining;
  }
}

bool isValidSessionPaymentSplit({
  required double amountDue,
  required double cash,
  required double card,
  required double wallet,
  required double credit,
  required double walletBalance,
  required double availableCredit,
  required bool canUseCredit,
}) {
  const maxAmount = 1000000000;
  final amounts = [amountDue, cash, card, wallet, credit];
  if (amounts.any(
    (amount) =>
        !amount.isFinite ||
        amount < 0 ||
        amount > maxAmount ||
        ((amount * 100) - (amount * 100).round()).abs() >= 0.000001,
  )) {
    return false;
  }
  if (amountDue <= 0 ||
      wallet > walletBalance ||
      credit > availableCredit ||
      (credit > 0 && !canUseCredit)) {
    return false;
  }
  final totalCents = [
    cash,
    card,
    wallet,
    credit,
  ].fold<int>(0, (sum, amount) => sum + (amount * 100).round());
  return totalCents == (amountDue * 100).round();
}

class PendingSessionRequest {
  const PendingSessionRequest({
    required this.id,
    required this.sessionId,
    required this.postId,
    required this.postName,
    required this.customerName,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String postId;
  final String postName;
  final String customerName;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory PendingSessionRequest.fromJson(
    Map<String, dynamic> json, {
    String timeZone = 'Africa/Algiers',
  }) {
    final rawPost = json['posts'];
    final rawCustomer = json['customers'];
    final createdAt = VenueTimeZone.parse(
      json['created_at'] as String?,
      timeZone,
    );
    if (createdAt == null) {
      throw const FormatException('Invalid session request timestamp');
    }
    return PendingSessionRequest(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      postId: json['post_id'] as String? ?? '',
      postName: rawPost is Map<String, dynamic>
          ? rawPost['name'] as String? ?? 'Post'
          : 'Post',
      customerName: rawCustomer is Map<String, dynamic>
          ? rawCustomer['full_name'] as String? ?? 'Client'
          : 'Client',
      type: json['type'] as String? ?? 'other',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      createdAt: createdAt,
    );
  }
}

class PendingStandaloneOrderRequest {
  const PendingStandaloneOrderRequest({
    required this.id,
    required this.customerName,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  final String id;
  final String customerName;
  final String productName;
  final int quantity;
  final double unitPrice;

  double get total => quantity * unitPrice;

  factory PendingStandaloneOrderRequest.fromJson(Map<String, dynamic> json) {
    final rawCustomer = json['customers'];
    final rawProduct = json['products'];
    return PendingStandaloneOrderRequest(
      id: json['id'] as String,
      customerName: rawCustomer is Map<String, dynamic>
          ? rawCustomer['full_name'] as String? ?? 'Client'
          : 'Client',
      productName: rawProduct is Map<String, dynamic>
          ? rawProduct['name'] as String? ?? 'Produit'
          : 'Produit',
      quantity: (json['quantity'] as num).toInt(),
      unitPrice: (json['expected_unit_price'] as num).toDouble(),
    );
  }
}

DateTime? _date(Object? value, String timeZone) {
  if (value is! String) return null;
  return VenueTimeZone.parse(value, timeZone);
}
