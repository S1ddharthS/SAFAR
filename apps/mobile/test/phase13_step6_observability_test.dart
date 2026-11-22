import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar_mobile/core/services/diagnostics_service.dart';
import 'package:safar_mobile/core/storage/json_store.dart';
import 'package:safar_mobile/core/storage/offline_queue.dart';

class InMemoryStore implements JsonStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  Future<void> deleteAll() async {
    _data.clear();
  }
}

void main() {
  setUp(() {
    DiagnosticsService.instance.clear();
  });

  group('DiagnosticsService & Sensitive Data Redaction', () {
    test('records network, realtime, and sync diagnostics', () {
      final diag = DiagnosticsService.instance;

      diag.recordNetwork('/api/trips', 'GET', 200, 45);
      diag.recordRealtime('itinerary.updated', 'live', tripId: 'trip_123');
      diag.recordSync('synced', 3, tripId: 'trip_123');

      final entries = diag.getEntries();
      expect(entries.length, 3);
      expect(entries[0].category, DiagnosticCategory.network);
      expect(entries[0].level, SafarDiagnosticLevel.info);
      expect(entries[1].category, DiagnosticCategory.realtime);
      expect(entries[2].category, DiagnosticCategory.sync);
    });

    test('redacts sensitive fields in diagnostic details', () {
      final diag = DiagnosticsService.instance;

      diag.record(
        category: DiagnosticCategory.auth,
        message: 'Auth attempt',
        details: {
          'user': 'aiko',
          'password': 'super_secret_password',
          'token': 'jwt_access_token_12345',
          'ticket': 'ws_ticket_xyz',
          'text_content': 'Secret trip notes',
          'lat': 35.6762,
          'lon': 139.6503,
          'safe_field': 'ok_to_log',
        },
      );

      final entries = diag.getEntries();
      expect(entries.length, 1);
      final details = entries.first.details!;

      expect(details['user'], 'aiko');
      expect(details['safe_field'], 'ok_to_log');
      expect(details['password'], '<redacted>');
      expect(details['token'], '<redacted>');
      expect(details['ticket'], '<redacted>');
      expect(details['text_content'], '<redacted>');
      expect(details['lat'], '<redacted>');
      expect(details['lon'], '<redacted>');
    });

    test('circular buffer trims to maxEntries without unbounded memory growth', () {
      final diag = DiagnosticsService(maxEntries: 5);

      for (var i = 0; i < 10; i++) {
        diag.record(
          category: DiagnosticCategory.network,
          message: 'Request $i',
        );
      }

      final entries = diag.getEntries(limit: 100);
      expect(entries.length, 5);
      expect(entries.first.message, 'Request 5');
      expect(entries.last.message, 'Request 9');
    });

    test('filters entries by category and min level', () {
      final diag = DiagnosticsService.instance;

      diag.record(
        category: DiagnosticCategory.network,
        message: 'Info network',
        level: SafarDiagnosticLevel.info,
      );
      diag.record(
        category: DiagnosticCategory.network,
        message: 'Warning network',
        level: SafarDiagnosticLevel.warning,
      );
      diag.record(
        category: DiagnosticCategory.framework,
        message: 'Error framework',
        level: SafarDiagnosticLevel.error,
      );

      final networkOnly = diag.getEntries(category: DiagnosticCategory.network);
      expect(networkOnly.length, 2);

      final errorsOnly = diag.getEntries(minLevel: SafarDiagnosticLevel.error);
      expect(errorsOnly.length, 1);
      expect(errorsOnly.first.message, 'Error framework');
    });

    test('captures global FlutterError and records without crashing', () {
      DiagnosticsService.setupGlobalErrorHandling();
      final diag = DiagnosticsService.instance;

      final testErrorDetails = FlutterErrorDetails(
        exception: Exception('Simulated framework layout crash'),
        library: 'widgets library',
        context: ErrorDescription('while building a widget'),
      );

      FlutterError.onError?.call(testErrorDetails);

      final errors = diag.getEntries(
        category: DiagnosticCategory.framework,
        minLevel: SafarDiagnosticLevel.error,
      );
      expect(errors.isNotEmpty, isTrue);
      expect(errors.first.message, contains('Simulated framework layout crash'));
    });
  });

  group('Offline Synchronization Monitoring & Recovery', () {
    test('tracks pending, syncing, and failed states with recovery', () async {
      final store = InMemoryStore();
      final queue = OfflineQueue(store);

      final capture1 = OfflineCapture(
        clientId: 'c1',
        tripId: 't1',
        text: 'First memory captured offline',
        capturedAt: '2026-11-21T10:00:00Z',
      );
      final capture2 = OfflineCapture(
        clientId: 'c2',
        tripId: 't1',
        text: 'Second memory captured offline',
        capturedAt: '2026-11-21T10:05:00Z',
      );

      // 1. Enqueue
      await queue.add(capture1);
      await queue.add(capture2);

      var pending = await queue.getPending();
      expect(pending.length, 2);
      expect(pending.every((c) => c.status == 'pending'), isTrue);

      // 2. Mark syncing
      await queue.markSyncing(['c1', 'c2']);
      var loaded = await queue.load();
      expect(loaded.every((c) => c.status == 'syncing'), isTrue);

      // 3. One fails, one succeeds
      await queue.markFailed('c2', 'Server rejected payload: text too short');
      await queue.remove(['c1']);

      var remaining = await queue.load();
      expect(remaining.length, 1);
      expect(remaining.first.clientId, 'c2');
      expect(remaining.first.status, 'failed');
      expect(remaining.first.retryCount, 1);
      expect(remaining.first.lastError, contains('text too short'));

      var failed = await queue.getFailed();
      expect(failed.length, 1);
      expect(failed.first.clientId, 'c2');

      // 4. Recovery: User initiates retry
      await queue.retryFailed();
      var retried = await queue.getPending();
      expect(retried.length, 1);
      expect(retried.first.status, 'pending');
      expect(retried.first.retryCount, 1); // preserved for telemetry
    });

    test('preserves offline items across simulated app restart', () async {
      final store = InMemoryStore();
      final queueBeforeRestart = OfflineQueue(store);

      await queueBeforeRestart.add(
        const OfflineCapture(
          clientId: 'c_persistent',
          tripId: 'trip_kyoto',
          text: 'Sunset at Fushimi Inari',
          capturedAt: '2026-11-21T18:30:00Z',
        ),
      );

      // Simulate app restart by instantiating new OfflineQueue over the same persistent store
      final queueAfterRestart = OfflineQueue(store);
      final loaded = await queueAfterRestart.load();

      expect(loaded.length, 1);
      expect(loaded.first.clientId, 'c_persistent');
      expect(loaded.first.tripId, 'trip_kyoto');
      expect(loaded.first.text, 'Sunset at Fushimi Inari');
      expect(loaded.first.status, 'pending');
    });
  });
}
