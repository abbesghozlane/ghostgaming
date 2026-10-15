import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/settings/data/venue_settings_repository.dart';

void main() {
  test('venue settings provide supported French timezone labels', () {
    expect(
      VenueSettingsRepository.timeZones['Africa/Algiers'],
      'Alger (UTC+1)',
    );
    expect(VenueSettingsRepository.timeZones.containsKey('UTC'), isFalse);
  });
}
