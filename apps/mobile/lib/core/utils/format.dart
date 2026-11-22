import 'package:intl/intl.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String formatDate(String? raw, {String fallback = '—'}) {
  if (raw == null || raw.isEmpty) return fallback;
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

String formatDateShort(String? raw, {String fallback = '—'}) {
  if (raw == null || raw.isEmpty) return fallback;
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return '${date.day} ${_months[date.month - 1]}';
}

String formatWeekday(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return '';
  return _weekdays[date.weekday - 1];
}

String formatTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return raw;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final display = hour % 12 == 0 ? 12 : hour % 12;
  return '$display:${minute.toString().padLeft(2, '0')} $suffix';
}

/// Formats an ISO timestamp or `HH:MM` value as a 12-hour clock time.
String formatClock(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = raw.contains('T') ? DateTime.tryParse(raw) : null;
  if (date == null) return formatTime(raw);
  final local = date.toLocal();
  return formatTime(
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}',
  );
}

String formatMoney(double? amount, [String currency = 'EUR']) {
  if (amount == null) return '—';
  try {
    return NumberFormat.simpleCurrency(
      name: currency,
      decimalDigits: amount == amount.roundToDouble() ? 0 : 2,
    ).format(amount);
  } on Object {
    return '${amount.toStringAsFixed(2)} $currency';
  }
}

String timeAgo(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return '';
  final diff = DateTime.now().toUtc().difference(date.toUtc());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDateShort(raw);
}

String titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(RegExp(r'[_\s-]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

String clockLabel(DateTime date) => DateFormat.Hm().format(date);

/// Inclusive list of calendar days between [start] and [end].
List<DateTime> tripDays(String startDate, String endDate, {int cap = 60}) {
  final start = DateTime.tryParse(startDate);
  final end = DateTime.tryParse(endDate);
  if (start == null || end == null || end.isBefore(start)) {
    return start == null ? const [] : [start];
  }
  final days = <DateTime>[];
  var cursor = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (!cursor.isAfter(last) && days.length < cap) {
    days.add(cursor);
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String compactNumber(double value) => NumberFormat.compact().format(value);
