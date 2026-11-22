// Phase 13 Step 5: Mobile Offline Capture & Synchronisation Test
// Tests offline queue persistence, app restart, sync against staging port 8020,
// retry idempotency, and conflict handling.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/network/api_client.dart';
import 'package:safar_mobile/core/network/cookie_jar.dart';
import 'package:safar_mobile/core/repositories/auth_repository.dart';
import 'package:safar_mobile/core/repositories/discovery_repository.dart';
import 'package:safar_mobile/core/repositories/trip_repository.dart';
import 'package:safar_mobile/core/storage/json_store.dart';
import 'package:safar_mobile/core/storage/offline_queue.dart';

const _miraEmail = 'mira@safar.demo';
const _password = 'safar-demo-123';

final _liveApi = Platform.environment['SAFAR_LIVE_API'];
final _skipLive = _liveApi == null ? 'SAFAR_LIVE_API not set' : null;

void main() {
  group('Phase 13 Step 5: Offline Capture & Sync (Live Staging API)', skip: _skipLive, () {
    test('Offline captures persist across app restart, sync with idempotency, and detect conflicts', () async {
      // 1. Establish persistent device storage
      final persistentStore = MemoryJsonStore();
      final jar = SafarCookieJar(persistentStore);
      final client = ApiClient(
        baseUrl: _liveApi ?? 'http://127.0.0.1:8020',
        jar: jar,
        store: persistentStore,
      );

      // Authenticate Mira
      final authRepo = AuthRepository(client);
      await authRepo.login(email: _miraEmail, password: _password);

      // Create a test trip
      final discoveryRepo = DiscoveryRepository(client);
      final dests = await discoveryRepo.destinations();
      final kyoto = dests.first;

      final tripRepo = TripRepository(client);
      final trip = await tripRepo.create(
        name: 'Offline Sync Resilience Trip',
        startDate: '2026-11-10',
        endDate: '2026-11-15',
        destinationId: kyoto.id,
        destinationName: kyoto.name,
        currency: 'EUR',
      );

      // 2. Capture memories while offline using OfflineQueue
      var offlineQueue = OfflineQueue(persistentStore);
      final capture1 = OfflineCapture(
        clientId: OfflineQueue.newClientId(),
        tripId: trip.id,
        text: 'Morning mist over Katsura river',
        capturedAt: '2026-11-11T07:30:00Z',
      );
      final capture2 = OfflineCapture(
        clientId: OfflineQueue.newClientId(),
        tripId: trip.id,
        text: 'Handcrafted ceramic teacup found in alley',
        capturedAt: '2026-11-11T10:15:00Z',
      );

      await offlineQueue.add(capture1);
      await offlineQueue.add(capture2);

      var queuedCaptures = await offlineQueue.load();
      expect(queuedCaptures.length, 2);

      // 3. Simulate App Restart before sync
      // Re-initialize queue and client from persistentStore
      offlineQueue = OfflineQueue(persistentStore);
      queuedCaptures = await offlineQueue.load();
      expect(queuedCaptures.length, 2, reason: 'Queued offline captures must survive app restart');
      expect(queuedCaptures[0].clientId, capture1.clientId);
      expect(queuedCaptures[1].clientId, capture2.clientId);

      // 4. Restore connectivity & Sync queued items to live Staging API
      final syncPayload = queuedCaptures.map((c) => {
        'client_id': c.clientId,
        'operation': 'memory_create',
        'payload': c.payload,
      }).toList();

      final syncResp = await client.post('/api/trips/${trip.id}/sync', data: syncPayload);
      expect(syncResp, isA<Map>());
      expect(syncResp['applied'], 2);
      expect(syncResp['skipped'], 0);
      expect(syncResp['rejected'], 0);

      // Remove synced items from offline queue
      await offlineQueue.remove([capture1.clientId, capture2.clientId]);
      final emptyQueue = await offlineQueue.load();
      expect(emptyQueue, isEmpty);

      // 5. Retry Idempotency: re-submit capture1 with the same client_id and same content
      final retryPayload = [
        {
          'client_id': capture1.clientId,
          'operation': 'memory_create',
          'payload': capture1.payload,
        }
      ];
      final retryResp = await client.post('/api/trips/${trip.id}/sync', data: retryPayload);
      expect(retryResp['applied'], 0);
      expect(retryResp['skipped'], 1, reason: 'Re-submitting identical client_id must be skipped idempotently');
      expect(retryResp['rejected'], 0);

      // 6. Conflicting update test: submit capture1 client_id with modified payload content
      final conflictPayload = [
        {
          'client_id': capture1.clientId,
          'operation': 'memory_create',
          'payload': {
            'kind': 'text',
            'text_content': 'ALTERED CONFLICTING TEXT CONTENT',
            'visibility': 'trip',
            'captured_at': '2026-11-11T07:30:00Z',
          },
        }
      ];
      final conflictResp = await client.post('/api/trips/${trip.id}/sync', data: conflictPayload);
      expect(conflictResp['rejected'], 1);
      final itemResults = conflictResp['results'] as List;
      expect(itemResults.first['reason'], contains('Client id reused with different content'));
    });
  });
}
