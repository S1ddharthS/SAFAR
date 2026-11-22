// Phase 13 Step 4: Multi-User Controlled Pilot & End-to-End Journey Live API Test
// Exercises Flutter repository layer against the staging API on port 8020.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/network/api_client.dart';
import 'package:safar_mobile/core/network/cookie_jar.dart';
import 'package:safar_mobile/core/repositories/auth_repository.dart';
import 'package:safar_mobile/core/repositories/discovery_repository.dart';
import 'package:safar_mobile/core/repositories/engine_repository.dart';
import 'package:safar_mobile/core/repositories/expense_repository.dart';
import 'package:safar_mobile/core/repositories/itinerary_repository.dart';
import 'package:safar_mobile/core/repositories/memory_repository.dart';
import 'package:safar_mobile/core/repositories/trip_repository.dart';
import 'package:safar_mobile/core/storage/json_store.dart';

const _miraEmail = 'mira@safar.demo';
const _aikoEmail = 'aiko@safar.demo';
const _password = 'safar-demo-123';

final _liveApi = Platform.environment['SAFAR_LIVE_API'];
final _skipLive = _liveApi == null ? 'SAFAR_LIVE_API not set' : null;

ApiClient _createClient(MemoryJsonStore store) {
  final jar = SafarCookieJar(store);
  return ApiClient(
    baseUrl: _liveApi ?? 'http://127.0.0.1:8020',
    jar: jar,
    store: store,
  );
}

void main() {
  group('Phase 13 Step 4: Multi-User Journey Verification (Live Staging API)', skip: _skipLive, () {
    test('End-to-end multi-user journey via Flutter repositories', () async {
      // 1. Mira logs in
      final miraStore = MemoryJsonStore();
      final miraClient = _createClient(miraStore);
      final miraAuth = AuthRepository(miraClient);
      final miraMe = await miraAuth.login(email: _miraEmail, password: _password);
      expect(miraMe.user.email, _miraEmail);
      expect(miraClient.accessToken, isNotEmpty);

      // 2. Discover Kyoto destination
      final discoveryRepo = DiscoveryRepository(miraClient);
      final destinations = await discoveryRepo.destinations();
      expect(destinations, isNotEmpty);
      final kyoto = destinations.first;

      // 3. Mira creates trip via TripRepository
      final tripRepo = TripRepository(miraClient);
      final trip = await tripRepo.create(
        name: 'Flutter Journey Validation Trip',
        startDate: '2026-10-15',
        endDate: '2026-10-22',
        destinationId: kyoto.id,
        destinationName: kyoto.name,
        currency: 'EUR',
      );
      expect(trip.id, isNotEmpty);
      expect(trip.name, 'Flutter Journey Validation Trip');

      // 4. Mira creates invitation for Aiko
      final invite = await tripRepo.createInvitation(
        trip.id,
        role: 'member',
        scope: 'full',
      );
      expect(invite.token, isNotEmpty);

      // 5. Aiko logs in with her own client session
      final aikoStore = MemoryJsonStore();
      final aikoClient = _createClient(aikoStore);
      final aikoAuth = AuthRepository(aikoClient);
      final aikoMe = await aikoAuth.login(email: _aikoEmail, password: _password);
      expect(aikoMe.user.email, _aikoEmail);

      // 6. Aiko previews and accepts the invitation
      final aikoTripRepo = TripRepository(aikoClient);
      final preview = await aikoTripRepo.previewInvitation(invite.token);
      expect(preview.tripName, trip.name);

      final joinedTrip = await aikoTripRepo.acceptInvitation(invite.token);
      expect(joinedTrip.id, trip.id);

      // 7. Verify both members see the trip and active membership
      final members = await aikoTripRepo.members(trip.id);
      expect(members.length, 2);
      final memberRoles = {for (final m in members) m.displayName: m.role};
      expect(memberRoles.values, containsAll(['owner', 'member']));

      // 8. Mira adds a confirmed itinerary item
      final itinRepo = ItineraryRepository(miraClient);
      await itinRepo.addItem(
        trip.id,
        day: '2026-10-16',
        title: 'Morning Arashiyama Walk',
        startTime: '09:00',
        endTime: '11:00',
        isProtected: true,
      );

      final currentItin = await itinRepo.get(trip.id);
      expect(currentItin.items.length, 1);
      expect(currentItin.items.first.title, 'Morning Arashiyama Walk');

      // 9. Generate recommendations via EngineRepository
      final engineRepo = EngineRepository(miraClient);
      final batch = await engineRepo.recommend(
        trip.id,
        mode: 'everyone_wins',
        forDate: '2026-10-17',
      );
      expect(batch.items, isNotEmpty);

      // 10. Propose an activity and vote
      final proposedActivityId = batch.items.first.activityId;
      final aikoItinRepo = ItineraryRepository(aikoClient);
      final proposal = await aikoItinRepo.createProposal(
        trip.id,
        title: 'Gion Evening Culture Walk',
        activityId: proposedActivityId,
        day: '2026-10-17',
        startTime: '16:00',
      );
      expect(proposal.id, isNotEmpty);

      // Both vote yes
      await aikoItinRepo.vote(trip.id, proposal.id, 'yes');
      await itinRepo.vote(trip.id, proposal.id, 'yes');

      // Mira approves proposal into confirmed itinerary
      await itinRepo.approve(trip.id, proposal.id);

      final updatedItin = await itinRepo.get(trip.id);
      expect(updatedItin.items.length, 2);

      // 11. Expenses tracking via ExpenseRepository
      final expenseRepo = ExpenseRepository(miraClient);
      await expenseRepo.create(
        trip.id,
        title: 'Bullet train tickets',
        amount: 280.0,
        category: 'transport',
        split: 'equal',
      );

      final balances = await expenseRepo.balances(trip.id);
      expect(balances.totalSpent, 280.0);

      // 12. Memories capture via MemoryRepository
      final memoryRepo = MemoryRepository(miraClient);
      final mem = await memoryRepo.create(
        trip.id,
        text: 'Temple gate bathed in sunset light',
        caption: 'Arashiyama Sunset',
        visibility: 'trip',
      );
      expect(mem.id, isNotEmpty);

      // 13. Disruption analysis via EngineRepository (Trip Rescue)
      final rescue = await engineRepo.analyzeRescue(
        trip.id,
        kind: 'rain',
        extraMinutes: 45,
      );
      expect(rescue.disruption.kind, 'rain');
      expect(rescue.requiresApproval, isTrue);
    });
  });
}
