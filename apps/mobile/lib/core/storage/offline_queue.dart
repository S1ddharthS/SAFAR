import 'dart:convert';
import 'dart:math';

import '../services/diagnostics_service.dart';
import 'json_store.dart';

/// A memory captured on the device while the API was unreachable. The queue
/// lives in secure storage; entries are removed only after the server reports
/// them applied or already known.
class OfflineCapture {
  const OfflineCapture({
    required this.clientId,
    required this.tripId,
    required this.text,
    required this.capturedAt,
    this.status = 'pending',
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptedAt,
  });

  final String clientId;
  final String tripId;
  final String text;
  final String capturedAt;
  final String status; // 'pending', 'syncing', 'failed'
  final int retryCount;
  final String? lastError;
  final String? lastAttemptedAt;

  OfflineCapture copyWith({
    String? status,
    int? retryCount,
    String? lastError,
    String? lastAttemptedAt,
  }) =>
      OfflineCapture(
        clientId: clientId,
        tripId: tripId,
        text: text,
        capturedAt: capturedAt,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
        lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      );

  Map<String, dynamic> get payload => {
        'kind': 'text',
        'text_content': text,
        'visibility': 'trip',
        'captured_at': capturedAt,
      };

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'trip_id': tripId,
        'text': text,
        'captured_at': capturedAt,
        'status': status,
        'retry_count': retryCount,
        if (lastError != null) 'last_error': lastError,
        if (lastAttemptedAt != null) 'last_attempted_at': lastAttemptedAt,
      };

  factory OfflineCapture.fromJson(Map<String, dynamic> json) => OfflineCapture(
        clientId: '${json['client_id'] ?? ''}',
        tripId: '${json['trip_id'] ?? ''}',
        text: '${json['text'] ?? ''}',
        capturedAt: '${json['captured_at'] ?? ''}',
        status: '${json['status'] ?? 'pending'}',
        retryCount: json['retry_count'] is int ? json['retry_count'] as int : 0,
        lastError: json['last_error'] as String?,
        lastAttemptedAt: json['last_attempted_at'] as String?,
      );
}

class OfflineQueue {
  OfflineQueue(this._store);

  static const _key = 'safar.offline.captures';

  final JsonStore _store;

  /// Server contract: client ids are 6–80 characters.
  static String newClientId() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = Random.secure().nextInt(1 << 32).toRadixString(36);
    return 'm$time$salt';
  }

  Future<List<OfflineCapture>> load() async {
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => OfflineCapture.fromJson(
                item.map((key, value) => MapEntry('$key', value)),
              ))
          .where((capture) => capture.clientId.isNotEmpty && capture.text.isNotEmpty)
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<List<OfflineCapture>> add(OfflineCapture capture) async {
    final current = await load();
    final next = [...current, capture];
    await save(next);
    DiagnosticsService.instance.recordSync(
      'enqueued',
      next.length,
      tripId: capture.tripId,
    );
    return next;
  }

  Future<void> markSyncing(Iterable<String> clientIds) async {
    final targetSet = clientIds.toSet();
    final current = await load();
    final next = current.map((c) {
      if (targetSet.contains(c.clientId)) {
        return c.copyWith(
          status: 'syncing',
          lastAttemptedAt: DateTime.now().toIso8601String(),
        );
      }
      return c;
    }).toList();
    await save(next);
    DiagnosticsService.instance.recordSync('syncing_started', targetSet.length);
  }

  Future<void> markFailed(String clientId, String error) async {
    final current = await load();
    final next = current.map((c) {
      if (c.clientId == clientId) {
        return c.copyWith(
          status: 'failed',
          retryCount: c.retryCount + 1,
          lastError: error,
          lastAttemptedAt: DateTime.now().toIso8601String(),
        );
      }
      return c;
    }).toList();
    await save(next);
    DiagnosticsService.instance.recordSync(
      'item_failed',
      1,
      error: error,
    );
  }

  Future<List<OfflineCapture>> getPending() async {
    final current = await load();
    return current.where((c) => c.status != 'failed').toList();
  }

  Future<List<OfflineCapture>> getFailed() async {
    final current = await load();
    return current.where((c) => c.status == 'failed').toList();
  }

  Future<List<OfflineCapture>> retryFailed() async {
    final current = await load();
    final next = current.map((c) {
      if (c.status == 'failed') {
        return c.copyWith(status: 'pending');
      }
      return c;
    }).toList();
    await save(next);
    DiagnosticsService.instance.recordSync('retry_initiated', next.length);
    return next;
  }

  Future<List<OfflineCapture>> remove(Iterable<String> clientIds) async {
    final settled = clientIds.toSet();
    final next =
        (await load()).where((capture) => !settled.contains(capture.clientId)).toList();
    await save(next);
    DiagnosticsService.instance.recordSync('settled_removed', settled.length);
    return next;
  }

  Future<void> save(List<OfflineCapture> captures) => _store.write(
        _key,
        jsonEncode(captures.map((capture) => capture.toJson()).toList()),
      );
}
