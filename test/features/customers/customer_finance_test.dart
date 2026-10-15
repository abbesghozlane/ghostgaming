import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/customers/domain/customer_order_policy.dart';
import 'package:ghostgaming/features/customers/data/customer_finance_repository.dart';
import 'package:ghostgaming/features/customers/domain/customer_session_selection.dart';

void main() {
  test(
    'financial operation errors explain balance and permission failures',
    () {
      expect(
        customerFinanceErrorMessage('REPAYMENT_EXCEEDS_BALANCE'),
        contains('dépasse le crédit'),
      );
      expect(
        customerFinanceErrorMessage('CREDIT_LIMIT_BELOW_BALANCE'),
        contains('inférieure au crédit utilisé'),
      );
      expect(
        customerFinanceErrorMessage('FORBIDDEN'),
        contains('autorisation'),
      );
    },
  );

  test(
    'pre-session paid orders can attach once to an open customer session',
    () {
      expect(
        canAttachPreSessionOrder(
          requestStatus: 'completed',
          orderSessionId: null,
          sessionStatus: 'active',
        ),
        isTrue,
      );
      expect(
        canAttachPreSessionOrder(
          requestStatus: 'completed',
          orderSessionId: 'existing-session',
          sessionStatus: 'active',
        ),
        isFalse,
      );
      expect(
        canAttachPreSessionOrder(
          requestStatus: 'pending',
          orderSessionId: null,
          sessionStatus: 'active',
        ),
        isFalse,
      );
      expect(
        canAttachPreSessionOrder(
          requestStatus: 'completed',
          orderSessionId: null,
          sessionStatus: 'closed',
        ),
        isFalse,
      );
    },
  );

  test(
    'deep links select their session instead of the first active session',
    () {
      final sessions = [
        {'id': 'session-a'},
        {'id': 'session-b'},
      ];

      expect(
        selectCustomerSession(
          sessions: sessions,
          requestedSessionId: 'session-b',
        )?['id'],
        'session-b',
      );
      expect(
        selectCustomerSession(
          sessions: sessions,
          selectedSessionId: 'session-b',
        )?['id'],
        'session-b',
      );
      expect(selectCustomerSession(sessions: sessions)?['id'], 'session-a');
    },
  );
}
