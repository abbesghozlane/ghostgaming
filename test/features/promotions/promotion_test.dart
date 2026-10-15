import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/promotions/data/promotion_repository.dart';

void main() {
  test('promotion is usable only within its active time window', () {
    final promotion = Promotion.fromJson({
      'id': 'promotion-id',
      'name': 'Heure calme',
      'description': null,
      'discount_percent': 15,
      'starts_at': '2026-10-04T10:00:00Z',
      'ends_at': '2026-10-04T12:00:00Z',
      'is_active': true,
    });

    expect(promotion.activeAt(DateTime.utc(2026, 10, 4, 11)), isTrue);
    expect(promotion.activeAt(DateTime.utc(2026, 10, 4, 12)), isFalse);
    expect(promotion.activeAt(DateTime.utc(2026, 10, 4, 9)), isFalse);
  });
}
