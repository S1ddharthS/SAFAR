import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/env.dart';
import 'models/common.dart';
import 'models/discovery.dart';
import 'models/engine.dart';
import 'models/expenses.dart';
import 'models/inspirations.dart';
import 'models/invitation.dart';
import 'models/itinerary.dart';
import 'models/memories.dart';
import 'models/monitoring.dart';
import 'models/planning.dart';
import 'models/social.dart';
import 'models/trip.dart';
import 'network/api_client.dart';
import 'network/api_exception.dart';
import 'network/cookie_jar.dart';
import 'repositories/assistant_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/companion_repository.dart';
import 'repositories/discovery_repository.dart';
import 'repositories/engine_repository.dart';
import 'repositories/expense_repository.dart';
import 'repositories/inspiration_repository.dart';
import 'repositories/itinerary_repository.dart';
import 'repositories/memory_repository.dart';
import 'repositories/social_repository.dart';
import 'repositories/trip_repository.dart';
import 'repositories/user_repository.dart';
import 'storage/json_store.dart';
import 'storage/offline_queue.dart';

final jsonStoreProvider = Provider<JsonStore>((ref) {
  // The browser owns cookies for the web verification build, so nothing
  // sensitive is written to web storage.
  if (kIsWeb) return MemoryJsonStore();
  return SecureJsonStore();
});

final offlineQueueProvider = Provider<OfflineQueue>(
  (ref) => OfflineQueue(ref.watch(jsonStoreProvider)),
);

final cookieJarProvider = Provider<SafarCookieJar>(
  (ref) => SafarCookieJar(ref.watch(jsonStoreProvider)),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: Env.apiBaseUrl,
    jar: ref.watch(cookieJarProvider),
    store: ref.watch(jsonStoreProvider),
  );
  ref.onDispose(() => client.dio.close(force: true));
  return client;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);
final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(apiClientProvider)),
);
final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => TripRepository(ref.watch(apiClientProvider)),
);
final itineraryRepositoryProvider = Provider<ItineraryRepository>(
  (ref) => ItineraryRepository(ref.watch(apiClientProvider)),
);
final engineRepositoryProvider = Provider<EngineRepository>(
  (ref) => EngineRepository(ref.watch(apiClientProvider)),
);
final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(apiClientProvider)),
);
final memoryRepositoryProvider = Provider<MemoryRepository>(
  (ref) => MemoryRepository(ref.watch(apiClientProvider)),
);
final discoveryRepositoryProvider = Provider<DiscoveryRepository>(
  (ref) => DiscoveryRepository(ref.watch(apiClientProvider)),
);
final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => AssistantRepository(ref.watch(apiClientProvider)),
);
final inspirationRepositoryProvider = Provider<InspirationRepository>(
  (ref) => InspirationRepository(ref.watch(apiClientProvider)),
);
final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => SocialRepository(ref.watch(apiClientProvider)),
);
final companionRepositoryProvider = Provider<CompanionRepository>(
  (ref) => CompanionRepository(ref.watch(apiClientProvider)),
);

// ---------------------------------------------------------------- account

final meProvider = FutureProvider<Me>(
  (ref) => ref.watch(userRepositoryProvider).me(),
);

final notificationsProvider = FutureProvider<NotificationFeed>(
  (ref) => ref.watch(userRepositoryProvider).notifications(),
);

// ---------------------------------------------------------------- trips

final tripsProvider = FutureProvider<List<Trip>>(
  (ref) => ref.watch(tripRepositoryProvider).list(),
);

final tripProvider = FutureProvider.family<Trip, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).get(tripId),
);

final membersProvider = FutureProvider.family<List<Member>, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).members(tripId),
);

final invitationsProvider = FutureProvider.family<List<TripInvitation>, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).invitations(tripId),
);

final invitationPreviewProvider = FutureProvider.family<InvitationPreview, String>(
  (ref, token) => ref.watch(tripRepositoryProvider).previewInvitation(token),
);

final itineraryProvider = FutureProvider.family<Itinerary, String>(
  (ref, tripId) => ref.watch(itineraryRepositoryProvider).get(tripId),
);

final proposalsProvider = FutureProvider.family<List<Proposal>, String>(
  (ref, tripId) =>
      ref.watch(itineraryRepositoryProvider).proposals(tripId, status: 'all'),
);

/// `null` means the engine has not produced a batch for this trip yet.
final engineProvider = FutureProvider.family<EngineBatch?, String>((
  ref,
  tripId,
) async {
  try {
    return await ref.watch(engineRepositoryProvider).latest(tripId);
  } on ApiException catch (error) {
    if (error.statusCode == 404) return null;
    rethrow;
  }
});

final expensesProvider = FutureProvider.family<ExpenseTotals, String>(
  (ref, tripId) => ref.watch(expenseRepositoryProvider).list(tripId),
);

final balancesProvider = FutureProvider.family<BalancesResponse, String>(
  (ref, tripId) => ref.watch(expenseRepositoryProvider).balances(tripId),
);

final pulseProvider = FutureProvider.family<PulseResponse, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).pulse(tripId),
);

final memoriesProvider = FutureProvider.family<MemoriesResponse, String>(
  (ref, tripId) => ref.watch(memoryRepositoryProvider).list(tripId),
);

final studioProvider = FutureProvider.family<Studio, String>(
  (ref, tripId) => ref.watch(memoryRepositoryProvider).studio(tripId),
);

final replayProvider = FutureProvider.family<ReplayResponse, String>(
  (ref, tripId) => ref.watch(memoryRepositoryProvider).replay(tripId),
);

final inspirationsProvider = FutureProvider.family<List<InspirationItem>, String>(
  (ref, tripId) => ref.watch(inspirationRepositoryProvider).list(tripId),
);

final tasksProvider = FutureProvider.family<List<TaskItem>, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).tasks(tripId),
);

// ---------------------------------------------------------------- discovery

final destinationsProvider = FutureProvider<List<Destination>>(
  (ref) => ref.watch(discoveryRepositoryProvider).destinations(),
);

final destinationProvider = FutureProvider.family<DestinationDetail, String>(
  (ref, id) => ref.watch(discoveryRepositoryProvider).destination(id),
);

class ActivitySearchQuery {
  const ActivitySearchQuery({
    required this.destinationId,
    this.query,
    this.lens = 'balanced',
    this.maxBudget,
    this.indoor = false,
    this.accessible = false,
    this.tags,
    this.limit = 30,
  });

  final String destinationId;
  final String? query;
  final String lens;
  final double? maxBudget;
  final bool indoor;
  final bool accessible;
  final String? tags;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is ActivitySearchQuery &&
      other.destinationId == destinationId &&
      other.query == query &&
      other.lens == lens &&
      other.maxBudget == maxBudget &&
      other.indoor == indoor &&
      other.accessible == accessible &&
      other.tags == tags &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
    destinationId,
    query,
    lens,
    maxBudget,
    indoor,
    accessible,
    tags,
    limit,
  );
}

final activitySearchProvider =
    FutureProvider.family<SearchResult, ActivitySearchQuery>(
      (ref, query) => ref.watch(discoveryRepositoryProvider).search(
        destinationId: query.destinationId,
        query: query.query,
        lens: query.lens,
        maxBudget: query.maxBudget,
        indoor: query.indoor,
        accessible: query.accessible,
        tags: query.tags,
        limit: query.limit,
      ),
    );

typedef PlaceRecord = ({String tripId, String activityId});

final placeDetailProvider = FutureProvider.family<PlaceDetail, PlaceRecord>(
  (ref, key) => ref
      .watch(discoveryRepositoryProvider)
      .placeDetail(key.tripId, key.activityId),
);

final placeReportsProvider =
    FutureProvider.family<List<PlaceReportItem>, PlaceRecord>(
      (ref, key) => ref
          .watch(discoveryRepositoryProvider)
          .placeReports(key.tripId, activityId: key.activityId),
    );

// ------------------------------------------------------- trip collaboration

final pactProvider = FutureProvider.family<Pact?, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).pact(tripId),
);

final branchesProvider = FutureProvider.family<List<Branch>, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).branches(tripId),
);

final missionsProvider = FutureProvider.family<List<Mission>, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).missions(tripId),
);

final taskSummaryProvider = FutureProvider.family<TaskSummary, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).taskSummary(tripId),
);

final capsulesProvider = FutureProvider.family<List<Capsule>, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).capsules(tripId),
);

final shadowplansProvider = FutureProvider.family<List<ShadowplanItem>, String>(
  (ref, tripId) => ref.watch(itineraryRepositoryProvider).shadowplans(tripId),
);

final effortProvider = FutureProvider.family<EffortBudget, String>(
  (ref, tripId) => ref.watch(itineraryRepositoryProvider).effort(tripId),
);

final fragilityProvider = FutureProvider.family<FragilityReport, String>(
  (ref, tripId) => ref.watch(itineraryRepositoryProvider).fragility(tripId),
);

typedef OpportunityKey = ({String tripId, String? day});

final opportunityProvider =
    FutureProvider.family<OpportunityClock, OpportunityKey>(
      (ref, key) => ref
          .watch(tripRepositoryProvider)
          .opportunityClock(key.tripId, on: key.day),
    );

final watchesProvider = FutureProvider.family<List<WatchItem>, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).materialWatches(tripId),
);

final groundRequestsProvider =
    FutureProvider.family<List<GroundRequestItem>, String>(
      (ref, tripId) => ref.watch(tripRepositoryProvider).groundRequests(tripId),
    );

final companionLinksProvider =
    FutureProvider.family<List<CompanionLink>, String>(
      (ref, tripId) => ref.watch(companionRepositoryProvider).list(tripId),
    );

final offlineSnapshotProvider = FutureProvider.family<OfflineSnapshot, String>(
  (ref, tripId) => ref.watch(memoryRepositoryProvider).offlineSnapshot(tripId),
);

final syncQueueProvider = FutureProvider.family<List<SyncQueueEntry>, String>(
  (ref, tripId) => ref.watch(memoryRepositoryProvider).syncQueue(tripId),
);

final circlesProvider = FutureProvider<List<Circle>>(
  (ref) => ref.watch(discoveryRepositoryProvider).circles(),
);

final circleProvider = FutureProvider.family<CircleDetail, String>(
  (ref, id) => ref.watch(discoveryRepositoryProvider).circle(id),
);

final contributorsProvider = FutureProvider<List<Contributor>>(
  (ref) => ref.watch(discoveryRepositoryProvider).contributors(),
);

final serendipityProvider = FutureProvider<SerendipityFeed>(
  (ref) => ref.watch(socialRepositoryProvider).feed(),
);

final connectionRequestsProvider =
    FutureProvider<List<ConnectionRequestItem>>(
      (ref) => ref.watch(socialRepositoryProvider).requests(),
    );

final threadProvider = FutureProvider<ThreadResponse>(
  (ref) => ref.watch(userRepositoryProvider).thread(),
);

class NearbyQuery {
  const NearbyQuery({
    required this.tripId,
    this.lat,
    this.lon,
    this.radiusKm = 5,
    this.category,
    this.limit = 20,
  });

  final String tripId;
  final double? lat;
  final double? lon;
  final double radiusKm;
  final String? category;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is NearbyQuery &&
      other.tripId == tripId &&
      other.lat == lat &&
      other.lon == lon &&
      other.radiusKm == radiusKm &&
      other.category == category &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(tripId, lat, lon, radiusKm, category, limit);
}

final nearbyProvider = FutureProvider.family<NearbyResponse, NearbyQuery>(
  (ref, query) => ref.watch(discoveryRepositoryProvider).nearby(
    query.tripId,
    lat: query.lat,
    lon: query.lon,
    radiusKm: query.radiusKm,
    category: query.category,
    limit: query.limit,
  ),
);

typedef ProposalRecord = ({String tripId, String proposalId});

final proposalDetailProvider = FutureProvider.family<Proposal, ProposalRecord>(
  (ref, key) => ref
      .watch(itineraryRepositoryProvider)
      .getProposal(key.tripId, key.proposalId),
);

/// Data scoped to the signed-in account. `AuthController` invalidates all of
/// these when a session starts so one person's cached trips, members or
/// invites can never surface in another account's session (and an error that
/// happened while signed out cannot outlive the next sign-in).
final sessionDataProviders = <ProviderOrFamily>[
  meProvider,
  notificationsProvider,
  tripsProvider,
  tripProvider,
  membersProvider,
  invitationsProvider,
  invitationPreviewProvider,
  itineraryProvider,
  proposalsProvider,
  engineProvider,
  expensesProvider,
  balancesProvider,
  pulseProvider,
  memoriesProvider,
  studioProvider,
  replayProvider,
  inspirationsProvider,
  tasksProvider,
  placeDetailProvider,
  placeReportsProvider,
  pactProvider,
  branchesProvider,
  missionsProvider,
  taskSummaryProvider,
  capsulesProvider,
  shadowplansProvider,
  effortProvider,
  fragilityProvider,
  opportunityProvider,
  watchesProvider,
  groundRequestsProvider,
  companionLinksProvider,
  offlineSnapshotProvider,
  syncQueueProvider,
  circlesProvider,
  circleProvider,
  contributorsProvider,
  serendipityProvider,
  connectionRequestsProvider,
  threadProvider,
  nearbyProvider,
  proposalDetailProvider,
];
