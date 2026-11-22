import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/models/monitoring.dart';
import 'package:safar_mobile/core/native/deep_links.dart';
import 'package:safar_mobile/core/realtime/trip_channel.dart';
import 'package:safar_mobile/core/storage/json_store.dart';
import 'package:safar_mobile/core/storage/offline_queue.dart';
import 'package:safar_mobile/features/trip/watch_screen.dart';

void main() {
  group('trip socket contract', () {
    test('parses event envelopes and rejects malformed frames', () {
      final event = TripEvent.tryParse(
        jsonEncode({
          'event': 'proposal.created',
          'at': '2026-11-20T10:00:00Z',
          'trip_id': 't1',
          'proposal_id': 'p1',
          'by': 'Mira',
        }),
      );
      expect(event, isNotNull);
      expect(event!.event, 'proposal.created');
      expect(event.at, '2026-11-20T10:00:00Z');
      expect(event.actor, 'Mira');

      expect(TripEvent.tryParse('not json'), isNull);
      expect(TripEvent.tryParse('{"at":"x"}'), isNull);
      expect(TripEvent.tryParse(42), isNull);
    });

    test('builds ws and wss URLs with an encoded ticket', () {
      expect(
        tripSocketUrl(
          apiBaseUrl: 'http://localhost:8010/',
          tripId: 't1',
          ticket: 'a b+c',
        ),
        'ws://localhost:8010/ws/trips/t1?token=a%20b%2Bc',
      );
      expect(
        tripSocketUrl(
          apiBaseUrl: 'https://api.example.test',
          tripId: 'abc',
          ticket: 'x',
        ),
        'wss://api.example.test/ws/trips/abc?token=x',
      );
    });

    test('backoff grows then caps at 30 seconds', () {
      expect(realtimeBackoff(0), const Duration(seconds: 1));
      expect(realtimeBackoff(1), const Duration(seconds: 2));
      expect(realtimeBackoff(4), const Duration(seconds: 15));
      expect(realtimeBackoff(5), const Duration(seconds: 30));
      expect(realtimeBackoff(99), const Duration(seconds: 30));
      expect(realtimeBackoff(-3), const Duration(seconds: 1));
    });
  });

  group('companion deep links', () {
    test('accepts the app scheme and https paths', () {
      expect(
        companionPathFromUri(Uri.parse('safar://companion/tok123')),
        '/companion/tok123',
      );
      expect(
        companionPathFromUri(Uri.parse('https://safar.test/companion/tok123')),
        '/companion/tok123',
      );
    });

    test('ignores unrelated links', () {
      expect(companionPathFromUri(Uri.parse('https://safar.test/trips/1')), isNull);
      expect(companionPathFromUri(Uri.parse('safar://invite/tok')), isNull);
      expect(companionPathFromUri(Uri.parse('https://safar.test/companion')), isNull);
    });
  });

  group('material watch values', () {
    test('describes seeded raw and wrapped values', () {
      expect(
        describeWatchValue('wheelchair_accessible', true),
        'step-free',
      );
      expect(
        describeWatchValue('wheelchair_accessible', {'value': false}),
        'not step-free',
      );
      expect(describeWatchValue('wheelchair_accessible', null), 'unknown');
      expect(describeWatchValue('price_estimate', 12), '€12');
    });

    test('formats opening hours maps', () {
      expect(
        describeWatchValue('opening_hours', {
          'mon': '09:00–17:00',
          'tue': '09:00–17:00',
        }),
        'Every day 09:00–17:00',
      );
      expect(
        describeWatchValue('opening_hours', {
          'mon': '09:00–17:00',
          'tue': 'closed',
        }),
        'Mon 09:00–17:00 · Tue closed',
      );
      expect(describeWatchValue('opening_hours', {}), 'unknown');
    });
  });

  group('companion public context', () {
    test('parses the server payload', () {
      final context = CompanionContext.fromJson({
        'purpose': 'vote',
        'question': 'Should we remove the tea ceremony?',
        'options': ['yes', 'no', 'abstain'],
        'trip': {'name': 'Kyoto', 'destination_name': 'Kyoto, Japan'},
        'target': {
          'kind': 'proposal',
          'id': 'p1',
          'title': 'Remove tea ceremony',
          'status': 'open',
          'registered_votes': {'yes': 2, 'no': 1},
        },
        'expires_at': '2026-11-21T10:00:00',
        'remaining_uses': 1,
        'anonymous_responses': 0,
        'disclosure': 'No identity is stored.',
      });
      expect(context.purpose, 'vote');
      expect(context.tripName, 'Kyoto');
      expect(context.options, ['yes', 'no', 'abstain']);
      expect(context.target.registeredVotes['yes'], 2);
      expect(context.remainingUses, 1);
    });
  });

  group('offline capture queue', () {
    test('stores, reloads and removes captures without touching others', () async {
      final queue = OfflineQueue(MemoryJsonStore());
      final first = OfflineCapture(
        clientId: OfflineQueue.newClientId(),
        tripId: 'trip-a',
        text: 'First note',
        capturedAt: '2026-11-20T10:00:00Z',
      );
      final second = OfflineCapture(
        clientId: OfflineQueue.newClientId(),
        tripId: 'trip-a',
        text: 'Second note',
        capturedAt: '2026-11-20T10:05:00Z',
      );
      final otherTrip = OfflineCapture(
        clientId: OfflineQueue.newClientId(),
        tripId: 'trip-b',
        text: 'Elsewhere',
        capturedAt: '2026-11-20T10:06:00Z',
      );
      await queue.add(first);
      await queue.add(second);
      await queue.add(otherTrip);

      final loaded = await queue.load();
      expect(loaded.map((capture) => capture.text), [
        'First note',
        'Second note',
        'Elsewhere',
      ]);

      await queue.remove([first.clientId]);
      final remaining = await queue.load();
      expect(remaining.map((capture) => capture.text), [
        'Second note',
        'Elsewhere',
      ]);
      expect(first.clientId.length, greaterThanOrEqualTo(6));
      expect(first.clientId.length, lessThanOrEqualTo(80));
      expect(first.payload['operation'], isNull);
      expect(first.payload['kind'], 'text');
      expect(first.payload['visibility'], 'trip');
    });

    test('survives corrupt storage', () async {
      final store = MemoryJsonStore();
      await store.write('safar.offline.captures', '{not json');
      final queue = OfflineQueue(store);
      expect(await queue.load(), isEmpty);
    });
  });
}
