import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/reports/data/reports_repository.dart';

void main() {
  group('ReportPeriod.dateRange', () {
    test('today and yesterday use midnight boundaries', () {
      final now = DateTime(2026, 10, 4, 19, 3);
      final today = ReportPeriod.today.dateRange(now);
      final yesterday = ReportPeriod.yesterday.dateRange(now);

      expect([today.start.year, today.start.month, today.start.day], [2026, 10, 4]);
      expect([today.end.year, today.end.month, today.end.day], [2026, 10, 5]);
      expect(
        [yesterday.start.year, yesterday.start.month, yesterday.start.day],
        [2026, 10, 3],
      );
      expect(yesterday.end, today.start);
    });

    test('week begins Monday and includes seven days', () {
      final range = ReportPeriod.thisWeek.dateRange(DateTime(2026, 10, 4));

      expect([range.start.year, range.start.month, range.start.day], [2026, 9, 28]);
      expect([range.end.year, range.end.month, range.end.day], [2026, 10, 5]);
    });

    test('month range handles the year boundary', () {
      final range = ReportPeriod.thisMonth.dateRange(DateTime(2026, 12, 15));

      expect([range.start.year, range.start.month, range.start.day], [2026, 12, 1]);
      expect([range.end.year, range.end.month, range.end.day], [2027, 1, 1]);
    });

    test('uses venue calendar day rather than the device calendar day', () {
      final range = ReportPeriod.today.dateRange(
        DateTime.utc(2026, 10, 4, 20, 30),
        timeZone: 'Asia/Dubai',
      );

      expect([range.start.year, range.start.month, range.start.day], [2026, 10, 5]);
      expect(range.start.toUtc(), DateTime.utc(2026, 10, 4, 20));
      expect(range.end.toUtc(), DateTime.utc(2026, 10, 5, 20));
    });

    test('calendar-day boundaries follow daylight-saving transitions', () {
      final range = ReportPeriod.today.dateRange(
        DateTime.utc(2026, 3, 29, 12),
        timeZone: 'Europe/Paris',
      );

      expect(range.start.toUtc(), DateTime.utc(2026, 3, 28, 23));
      expect(range.end.toUtc(), DateTime.utc(2026, 3, 29, 22));
      expect(range.end.difference(range.start), const Duration(hours: 23));
    });
  });
}
