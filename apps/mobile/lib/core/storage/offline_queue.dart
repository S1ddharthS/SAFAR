import 'dart:convert';
import 'dart:math';

import 'json_store.dart';

const _storageKey = 'safar.offline.captures';

/// One memory captured on the device before connectivity is available.
///
/// [clientId] is the idempotency key sent to `/api/trips/{id}/sync`; replaying
/// the same id with the same payload is safe. The queue never edits the trip
/// itinerary and never changes a confirmed plan.
class OfflineCapture {
  const OfflineCapture({
    required this.clientId,
    required this.tripId,
    required this.text,
    required this.capturedAt,
    this.status = 'pending',
    this.retryCount = 0,
    this.lastError,
  });

  final String clientId;
  final String tripId;
  final String text;
  final String capturedAt;
  final String status;
  final int retryCount;
  final String? lastError;

  /// Payload accepted by the backend `MemoryCreate` schema.
  Map<String, dynamic> get payload => <String, dynamic>{
    'kind': 'text',
    'visibility': 'trip',
    'text_content': text,
    'captured_at': capturedAt,
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'clientId': clientId,
    'tripId': tripId,
    'text': text,
    'capturedAt': capturedAt,
    'status': status,
    'retryCount': retryCount,
    'lastError': lastError,
  };

  factory OfflineCapture.fromJson(Map<String, dynamic> json) => OfflineCapture(
    clientId: (json['clientId'] ?? '') as String,
    tripId: (json['tripId'] ?? '') as String,
    text: (json['text'] ?? '') as String,
    capturedAt: (json['capturedAt'] ?? '') as String,
    status: (json['status'] ?? 'pending') as String,
    retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
    lastError: json['lastError'] as String?,
  );

  OfflineCapture copyWith({
    String? status,
    int? retryCount,
    String? lastError,
    bool clearLastError = false,
  }) => OfflineCapture(
    clientId: clientId,
    tripId: tripId,
    text: text,
    capturedAt: capturedAt,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
  );
}

/// Durable, idempotent queue of offline captures.
///
/// All state lives in the injected [JsonStore], so a new [OfflineQueue] over
/// the same store sees the same captures after an app restart. Corrupt or
/// unreadable storage degrades to an empty queue rather than crashing the
/// offline screen.
class OfflineQueue {
  OfflineQueue(this._store);

  final JsonStore _store;
  static final Random _random = Random.secure();

  /// Stable, collision-resistant client id without adding a UUID dependency.
  static String newClientId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = List<int>.generate(8, (_) => _random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'offline-$stamp-$entropy';
  }

  Future<List<OfflineCapture>> load() async {
    final raw = await _store.read(_storageKey);
    if (raw == null || raw.trim().isEmpty) return <OfflineCapture>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <OfflineCapture>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(OfflineCapture.fromJson)
          .where((capture) => capture.clientId.isNotEmpty)
          .toList(growable: true);
    } on FormatException {
      return <OfflineCapture>[];
    } on TypeError {
      return <OfflineCapture>[];
    }
  }

  Future<void> _save(List<OfflineCapture> captures) async {
    await _store.write(
      _storageKey,
      jsonEncode(captures.map((capture) => capture.toJson()).toList()),
    );
  }

  Future<void> add(OfflineCapture capture) async {
    final captures = await load();
    final index = captures.indexWhere((item) => item.clientId == capture.clientId);
    if (index >= 0) {
      // Same id means the same idempotent item: keep the original record.
      return;
    }
    captures.add(capture);
    await _save(captures);
  }

  Future<void> remove(Iterable<String> clientIds) async {
    final settled = clientIds.toSet();
    if (settled.isEmpty) return;
    final captures = await load();
    await _save(
      captures.where((capture) => !settled.contains(capture.clientId)).toList(),
    );
  }

  Future<List<OfflineCapture>> getPending() async {
    final captures = await load();
    return captures.where((capture) => capture.status == 'pending').toList();
  }

  Future<List<OfflineCapture>> getFailed() async {
    final captures = await load();
    return captures.where((capture) => capture.status == 'failed').toList();
  }

  Future<void> markSyncing(List<String> clientIds) async {
    final targets = clientIds.toSet();
    final captures = await load();
    await _save([
      for (final capture in captures)
        if (targets.contains(capture.clientId))
          capture.copyWith(status: 'syncing')
        else
          capture,
    ]);
  }

  Future<void> markFailed(String clientId, String error) async {
    final captures = await load();
    await _save([
      for (final capture in captures)
        if (capture.clientId == clientId)
          capture.copyWith(
            status: 'failed',
            retryCount: capture.retryCount + 1,
            lastError: error,
          )
        else
          capture,
    ]);
  }

  /// Returns failed captures to the pending state, keeping the retry count
  /// for telemetry and clearing the previous error message.
  Future<void> retryFailed() async {
    final captures = await load();
    await _save([
      for (final capture in captures)
        if (capture.status == 'failed')
          capture.copyWith(
            status: 'pending',
            clearLastError: true,
          )
        else
          capture,
    ]);
  }
}
