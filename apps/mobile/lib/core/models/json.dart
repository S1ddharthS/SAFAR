Map<String, dynamic> jsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const {};
}

List<dynamic> jsonList(dynamic value) => value is List ? value : const [];

String? jsonString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return null;
}

String jsonText(dynamic value, [String fallback = '']) =>
    jsonString(value) ?? fallback;

int jsonInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? jsonIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double jsonDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? jsonDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool jsonBool(dynamic value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

List<String> jsonStringList(dynamic value) =>
    jsonList(value).map((item) => jsonText(item)).where((s) => s.isNotEmpty).toList();

List<T> jsonObjects<T>(
  dynamic value,
  T Function(Map<String, dynamic> json) decode,
) => jsonList(value).map((item) => decode(jsonMap(item))).toList();

DateTime? jsonDate(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Parses a `YYYY-MM-DD` calendar date without applying a timezone.
DateTime? shortDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split('-');
  if (parts.length != 3) return DateTime.tryParse(value);
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}
