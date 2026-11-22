import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/utils/format.dart';

void main() {
  group('date and time formatting', () {
    test('formats calendar dates', () {
      expect(formatDate('2026-03-08'), '8 Mar 2026');
      expect(formatDateShort('2026-03-08'), '8 Mar');
      expect(formatWeekday('2026-03-08'), 'Sunday');
    });

    test('returns fallbacks for missing values', () {
      expect(formatDate(null), '—');
      expect(formatDate(''), '—');
      expect(formatDateShort(null, fallback: 'TBD'), 'TBD');
      expect(formatWeekday(null), '');
    });

    test('formats 24-hour strings as 12-hour clock times', () {
      expect(formatTime('09:05'), '9:05 AM');
      expect(formatTime('13:45'), '1:45 PM');
      expect(formatTime('00:00'), '12:00 AM');
      expect(formatTime('12:30'), '12:30 PM');
    });

    test('formatClock accepts ISO timestamps and plain times', () {
      expect(formatClock('13:45'), '1:45 PM');
      final iso = DateTime(2026, 3, 8, 18, 5).toIso8601String();
      expect(formatClock(iso), '6:05 PM');
      expect(formatClock(null), '');
    });

    test('tripDays lists inclusive calendar days', () {
      final days = tripDays('2026-03-08', '2026-03-10');
      expect(days.map(isoDate), ['2026-03-08', '2026-03-09', '2026-03-10']);
    });

    test('tripDays handles inverted ranges', () {
      expect(tripDays('2026-03-10', '2026-03-08'), hasLength(1));
    });

    test('timeAgo describes recent timestamps', () {
      final now = DateTime.now().toUtc();
      expect(timeAgo(now.toIso8601String()), 'just now');
      expect(
        timeAgo(now.subtract(const Duration(minutes: 5)).toIso8601String()),
        '5m ago',
      );
      expect(
        timeAgo(now.subtract(const Duration(hours: 3)).toIso8601String()),
        '3h ago',
      );
      expect(timeAgo(null), '');
    });

    test('titleCase normalises separators', () {
      expect(titleCase('group_experience-engine'), 'Group Experience Engine');
      expect(titleCase('rain'), 'Rain');
    });

    test('formats money with currency', () {
      expect(formatMoney(120, 'EUR'), contains('120'));
      expect(formatMoney(null), '—');
    });
  });
}
