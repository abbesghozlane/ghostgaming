import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/sessions/domain/session_dashboard_models.dart';

void main() {
  test('transfer targets exclude the current and occupied posts', () {
    const session = ActiveGamingSession(
      id: 'session',
      number: 1,
      postId: 'post-1',
      gameId: 'game',
      status: 'active',
      startedAt: null,
      plannedDurationSeconds: 0,
      totalPausedSeconds: 0,
      matchCount: 1,
      game: null,
      postName: 'Post 1',
      customerName: null,
    );
    const posts = [
      GamingPost(
        id: 'post-1',
        name: 'Post 1',
        number: 1,
        device: 'ps5',
        status: 'playing',
      ),
      GamingPost(
        id: 'post-2',
        name: 'Post 2',
        number: 2,
        device: 'ps5',
        status: 'available',
      ),
      GamingPost(
        id: 'post-3',
        name: 'Post 3',
        number: 3,
        device: 'ps4',
        status: 'reserved',
      ),
      GamingPost(
        id: 'post-4',
        name: 'Post 4',
        number: 4,
        device: 'pc',
        status: 'maintenance',
      ),
    ];

    expect(transferablePosts(posts, session).map((post) => post.id), [
      'post-2',
      'post-3',
    ]);
  });

  test('standalone order request totals use the requested quantity', () {
    final request = PendingStandaloneOrderRequest.fromJson({
      'id': 'request-1',
      'quantity': 3,
      'expected_unit_price': 125.5,
      'customers': {'full_name': 'Client'},
      'products': {'name': 'Boisson'},
    });

    expect(request.customerName, 'Client');
    expect(request.productName, 'Boisson');
    expect(request.total, 376.5);
  });

  test('accepts exact split payments within wallet and credit balances', () {
    expect(
      isValidSessionPaymentSplit(
        amountDue: 100,
        cash: 20,
        card: 30,
        wallet: 25,
        credit: 25,
        walletBalance: 25,
        availableCredit: 25,
        canUseCredit: true,
      ),
      isTrue,
    );
  });

  test(
    'rejects negative, over-balance, unauthorized, or fractional-cent lines',
    () {
      bool valid({
        double cash = 100,
        double wallet = 0,
        double credit = 0,
        bool canUseCredit = true,
      }) => isValidSessionPaymentSplit(
        amountDue: 100,
        cash: cash,
        card: 0,
        wallet: wallet,
        credit: credit,
        walletBalance: 50,
        availableCredit: 50,
        canUseCredit: canUseCredit,
      );

      expect(valid(cash: -1, wallet: 101), isFalse);
      expect(valid(cash: 50, wallet: 50.01), isFalse);
      expect(valid(cash: 50, credit: 50, canUseCredit: false), isFalse);
      expect(valid(cash: 99.999), isFalse);
    },
  );
}
