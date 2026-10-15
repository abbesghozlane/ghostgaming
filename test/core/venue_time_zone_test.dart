import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/utils/venue_time_zone.dart';

void main() {
  test('interprets a booking wall time in the venue timezone', () {
    final utc = VenueTimeZone.toUtc(
      DateTime(2026, 10, 4, 12, 30),
      'Africa/Algiers',
    );

    expect(utc, DateTime.utc(2026, 10, 4, 11, 30));
  });

  test('interprets UTC-shaped picker values as venue wall time', () {
    final utc = VenueTimeZone.toUtc(
      DateTime.utc(2026, 10, 4, 12, 30),
      'Africa/Algiers',
    );

    expect(utc, DateTime.utc(2026, 10, 4, 11, 30));
  });

  test('parses an instant into venue-local date and time fields', () {
    final local = VenueTimeZone.parse('2026-10-04T11:30:00Z', 'Africa/Algiers');

    expect(local, isNotNull);
    expect(
      [local!.year, local.month, local.day, local.hour, local.minute],
      [2026, 10, 4, 12, 30],
    );
  });
}
