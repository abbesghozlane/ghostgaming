import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/reservations/data/reservation_repository.dart';

void main() {
  test('reservation data is parsed with localized times and linked names', () {
    final reservation = ReservationItem.fromJson({
      'id': 'reservation-id',
      'post_id': 'post-id',
      'customer_id': 'customer-id',
      'starts_at': '2026-10-05T16:00:00Z',
      'ends_at': '2026-10-05T17:00:00Z',
      'status': 'confirmed',
      'posts': {'name': 'Post 04'},
      'customers': {'full_name': 'Samir'},
    });

    expect(reservation.postName, 'Post 04');
    expect(reservation.customerName, 'Samir');
    expect(reservation.status, 'confirmed');
    expect(reservationStatusLabel(reservation.status), 'Confirmée');
    expect(reservation.startsAt, DateTime.utc(2026, 10, 5, 16).toLocal());
  });

  test('reservation errors explain conflicts and invalid durations', () {
    expect(
      reservationErrorMessage('RESERVATION_SLOT_TAKEN'),
      contains('autre horaire'),
    );
    expect(
      reservationErrorMessage('INVALID_RESERVATION_DURATION'),
      contains('durée'),
    );
  });
}
