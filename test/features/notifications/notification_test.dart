import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/utils/venue_time_zone.dart';
import 'package:ghostgaming/features/notifications/data/notification_repository.dart';

void main() {
  test('notification parses persisted fields and local creation time', () {
    final notification = AppNotification.fromJson({
      'id': 'notification-id',
      'type': 'session_request',
      'title': 'Demande reçue',
      'body': 'POST 05 demande +1 match',
      'reference_type': 'session',
      'reference_id': 'session-id',
      'data': {'session_id': 'session-id'},
      'is_read': false,
      'created_at': '2026-10-04T12:30:00Z',
    });

    expect(notification.title, 'Demande reçue');
    expect(notification.data['session_id'], 'session-id');
    expect(notification.isRead, isFalse);
    expect(
      notification.createdAt,
      VenueTimeZone.parse('2026-10-04T12:30:00Z', 'Africa/Algiers'),
    );
    expect(
      notification.destinationForRole('employee'),
      '/home?sessionId=session-id',
    );
  });

  test('notification destinations open the referenced entity by role', () {
    AppNotification notification({
      required String referenceType,
      String? referenceId,
      Map<String, dynamic> data = const {},
    }) => AppNotification(
      id: 'notification-id',
      type: 'update',
      title: 'Mise à jour',
      body: null,
      referenceType: referenceType,
      referenceId: referenceId,
      data: data,
      isRead: false,
      createdAt: DateTime.utc(2026, 10, 4),
    );

    expect(
      notification(
        referenceType: 'reservation',
        referenceId: 'reservation-id',
      ).destinationForRole('customer'),
      '/booking?reservationId=reservation-id',
    );
    expect(
      notification(
        referenceType: 'session_request',
        referenceId: 'request-id',
        data: {'session_id': 'session-id'},
      ).destinationForRole('customer'),
      '/customer/home?sessionId=session-id',
    );
    expect(
      notification(
        referenceType: 'session',
        referenceId: 'session-id',
      ).destinationForRole('owner'),
      '/home?sessionId=session-id',
    );
  });

  test('order notifications open invoice history for both roles', () {
    final customer = AppNotification.fromJson({
      'id': 'customer-order',
      'type': 'standalone_order_completed',
      'title': 'Commande payée',
      'body': 'Facture n° 12',
      'reference_type': 'order',
      'reference_id': 'order-id',
      'data': const {},
      'is_read': false,
      'created_at': '2026-10-05T10:00:00Z',
    });

    expect(customer.destinationForRole('customer'), '/invoices');
    expect(customer.destinationForRole('owner'), '/invoices');
  });
}
