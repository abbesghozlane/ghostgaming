import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/programs/data/program_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late ProgramRepository repository;

  setUp(() {
    client = SupabaseClient('http://localhost:54321', 'test-key');
    repository = ProgramRepository(client);
  });

  tearDown(() {
    client.dispose();
  });

  test('rejects membership plans outside supported duration bounds', () async {
    await expectLater(
      repository.saveMembershipPlan(
        venueId: 'venue-id',
        name: 'Monthly',
        durationDays: 0,
        benefits: 'Benefits are informational',
      ),
      throwsA(
        isA<ProgramException>().having(
          (error) => error.code,
          'code',
          'INVALID_MEMBERSHIP_PLAN',
        ),
      ),
    );
  });

  test('rejects package prices that are not positive finite amounts', () async {
    await expectLater(
      repository.savePackage(
        name: 'Play pack',
        description: '',
        price: double.infinity,
        gamingMinutes: 60,
        items: const [],
      ),
      throwsA(isA<ProgramException>()),
    );
  });

  test('rejects duplicate products in package contents', () async {
    await expectLater(
      repository.savePackage(
        name: 'Play pack',
        description: '',
        price: 1000,
        gamingMinutes: 60,
        items: const [
          {'product_id': 'product-id', 'quantity': 1},
          {'product_id': 'product-id', 'quantity': 2},
        ],
      ),
      throwsA(isA<ProgramException>()),
    );
  });
}
