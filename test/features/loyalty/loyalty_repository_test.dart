import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/loyalty/data/loyalty_repository.dart';

void main() {
  test('parses a reward with unlimited stock', () {
    final reward = LoyaltyReward.fromJson({
      'id': 'reward-1',
      'name': 'Session bonus',
      'description': null,
      'points_cost': 120,
      'stock_quantity': null,
      'is_active': true,
    });

    expect(reward.pointsCost, 120);
    expect(reward.stockQuantity, isNull);
    expect(reward.isActive, isTrue);
  });

  test('parses customer redemption details and local timestamp', () {
    final redemption = LoyaltyRedemption.fromJson({
      'id': 'redemption-1',
      'customer_id': 'customer-1',
      'status': 'pending',
      'points_cost': 80,
      'note': null,
      'created_at': '2026-10-04T10:00:00Z',
      'customers': {'full_name': 'Client'},
      'loyalty_rewards': {'name': 'Session bonus'},
    });

    expect(redemption.customerName, 'Client');
    expect(redemption.rewardName, 'Session bonus');
    expect(redemption.pointsCost, 80);
    expect(redemption.createdAt.isUtc, isFalse);
  });

  test('rejects a redemption with an invalid timestamp', () {
    expect(
      () => LoyaltyRedemption.fromJson({
        'id': 'redemption-1',
        'customer_id': 'customer-1',
        'status': 'pending',
        'points_cost': 80,
        'note': null,
        'created_at': 'not-a-date',
      }),
      throwsFormatException,
    );
  });
}
