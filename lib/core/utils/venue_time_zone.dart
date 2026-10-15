import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class VenueTimeZone {
  VenueTimeZone._();

  static bool _initialized = false;

  static timezone.Location location(String timeZone) {
    if (!_initialized) {
      timezone_data.initializeTimeZones();
      _initialized = true;
    }
    return timezone.getLocation(timeZone);
  }

  static DateTime now(String timeZone, {DateTime? instant}) =>
      timezone.TZDateTime.from(instant ?? DateTime.now(), location(timeZone));

  static DateTime dateTime(
    String timeZone, {
    required int year,
    required int month,
    int day = 1,
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
    int microsecond = 0,
  }) => timezone.TZDateTime(
    location(timeZone),
    year,
    month,
    day,
    hour,
    minute,
    second,
    millisecond,
    microsecond,
  );

  static DateTime toUtc(DateTime wallTime, String timeZone) {
    return dateTime(
      timeZone,
      year: wallTime.year,
      month: wallTime.month,
      day: wallTime.day,
      hour: wallTime.hour,
      minute: wallTime.minute,
      second: wallTime.second,
      millisecond: wallTime.millisecond,
      microsecond: wallTime.microsecond,
    ).toUtc();
  }

  static DateTime? parse(String? timestamp, String timeZone) {
    final instant = DateTime.tryParse(timestamp ?? '');
    return instant == null
        ? null
        : timezone.TZDateTime.from(instant, location(timeZone));
  }
}
