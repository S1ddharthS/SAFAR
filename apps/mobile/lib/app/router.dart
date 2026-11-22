import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/native/pending_route.dart';
import '../core/providers.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/safar_widgets.dart';
import '../features/assistant/assistant_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/companion/companion_public_screen.dart';
import '../features/discover/destination_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/discover/place_screen.dart';
import '../features/home/dashboard_screen.dart';
import '../features/profile/journey_dna_screen.dart';
import '../features/profile/notifications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/settings_screen.dart';
import '../features/trip/branches_screen.dart';
import '../features/trip/circles_screen.dart';
import '../features/trip/companion_screen.dart';
import '../features/trip/connections_screen.dart';
import '../features/trip/contributors_screen.dart';
import '../features/trip/engine_screen.dart';
import '../features/trip/expenses_screen.dart';
import '../features/trip/ground_screen.dart';
import '../features/trip/import_screen.dart';
import '../features/trip/itinerary_screen.dart';
import '../features/trip/invitation_screen.dart';
import '../features/trip/memories_screen.dart';
import '../features/trip/members_screen.dart';
import '../features/trip/missions_screen.dart';
import '../features/trip/more_hub_screen.dart';
import '../features/trip/nearby_screen.dart';
import '../features/trip/negotiate_screen.dart';
import '../features/trip/offline_screen.dart';
import '../features/trip/opportunity_screen.dart';
import '../features/trip/pact_screen.dart';
import '../features/trip/plan_intelligence_screen.dart';
import '../features/trip/proposals_screen.dart';
import '../features/trip/pulse_screen.dart';
import '../features/trip/replay_screen.dart';
import '../features/trip/rescue_screen.dart';
import '../features/trip/studio_screen.dart';
import '../features/trip/tasks_screen.dart';
import '../features/trip/thread_screen.dart';
import '../features/trip/trip_overview_screen.dart';
import '../features/trip/twin_screen.dart';
import '../features/trip/watch_screen.dart';
import '../features/trips/trip_create_screen.dart';
import '../features/trips/trip_list_screen.dart';
import 'shell.dart';

final _rootNavigator = GlobalKey<NavigatorState>(debugLabel: 'root');
final _dashboardNavigator = GlobalKey<NavigatorState>(debugLabel: 'dashboard');
final _discoverNavigator = GlobalKey<NavigatorState>(debugLabel: 'discover');
final _tripsNavigator = GlobalKey<NavigatorState>(debugLabel: 'trips');
final _assistantNavigator = GlobalKey<NavigatorState>(debugLabel: 'assistant');
final _profileNavigator = GlobalKey<NavigatorState>(debugLabel: 'profile');

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(onboardingSeenProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  final router = GoRouter(
    navigatorKey: _rootNavigator,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      // One-Link Companion answers are public: the signed token is the only
      // credential and no session is required.
      if (location.startsWith('/companion/')) return null;
      final onboarded = ref.read(onboardingSeenProvider);
      final auth = ref.read(authControllerProvider);
      final atSplash = location == '/splash';
      final onOnboarding = location == '/welcome';
      final onAuthPage = location == '/login' || location == '/register';

      if (onboarded == null || auth.status == AuthStatus.unknown) {
        return atSplash ? null : '/splash';
      }
      if (!onboarded) {
        return onOnboarding ? null : '/welcome';
      }
      if (!auth.signedIn) {
        return onAuthPage ? null : '/login';
      }
      if (atSplash || onOnboarding || onAuthPage) {
        return PendingRoute.take('/dashboard');
      }
      return null;
    },
    errorBuilder: (context, state) => _NotFoundScreen(
      location: state.uri.toString(),
    ),
    routes: [
      GoRoute(
        path: '/splash',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/companion/:token',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => CompanionPublicScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: '/invite/:token',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => InvitationScreen(
          token: state.pathParameters['token']!,
        ),
      ),
      GoRoute(
        path: '/trips/new',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const TripCreateScreen(),
      ),
      GoRoute(
        path: '/trips/:tripId',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) =>
            TripOverviewScreen(tripId: state.pathParameters['tripId']!),
        routes: [
          GoRoute(
            path: 'members',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                MembersScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'itinerary',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ItineraryScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'engine',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                EngineScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'proposals',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ProposalsScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'expenses',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ExpensesScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'pulse',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                PulseScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'rescue',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                RescueScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'memories',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                MemoriesScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'more',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                MoreHubScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'companion',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                CompanionScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'tasks',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                TasksScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'watch',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                WatchScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'offline',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                OfflineScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'pact',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                PactScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'twin',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                TwinScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'plan',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                PlanIntelligenceScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'opportunity',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                OpportunityScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'branches',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                BranchesScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'nearby',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                NearbyScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'ground',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                GroundScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'missions',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                MissionsScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'connections',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ConnectionsScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'thread',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ThreadScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'contributors',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ContributorsScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'circles',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                CirclesScreen(tripId: state.pathParameters['tripId']!),
            routes: [
              GoRoute(
                path: ':circleId',
                parentNavigatorKey: _rootNavigator,
                builder: (context, state) => CircleDetailScreen(
                  tripId: state.pathParameters['tripId']!,
                  circleId: state.pathParameters['circleId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'negotiate',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                NegotiateScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'studio',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                StudioScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'replay',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ReplayScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'import',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) =>
                ImportScreen(tripId: state.pathParameters['tripId']!),
          ),
          GoRoute(
            path: 'assistant',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) => _TripAssistant(
              tripId: state.pathParameters['tripId']!,
            ),
          ),
          GoRoute(
            path: 'places/:activityId',
            parentNavigatorKey: _rootNavigator,
            builder: (context, state) => PlaceScreen(
              tripId: state.pathParameters['tripId']!,
              activityId: state.pathParameters['activityId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/destinations/:destinationId',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => DestinationScreen(
          destinationId: state.pathParameters['destinationId']!,
        ),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/journey-dna',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const JourneyDnaScreen(),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigator,
        builder: (context, state) => const SettingsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            SafarShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _dashboardNavigator,
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _discoverNavigator,
            routes: [
              GoRoute(
                path: '/discover',
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _tripsNavigator,
            routes: [
              GoRoute(
                path: '/trips',
                builder: (context, state) => const TripListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _assistantNavigator,
            routes: [
              GoRoute(
                path: '/assistant',
                builder: (context, state) => const AssistantScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileNavigator,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _TripAssistant extends ConsumerWidget {
  const _TripAssistant({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider(tripId)).valueOrNull;
    return AssistantScreen(tripId: tripId, tripName: trip?.name);
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: SafeArea(
        child: SafarEmpty(
          icon: Icons.explore_off_outlined,
          title: 'This path does not exist',
          message: 'SAFAR could not find “$location”.',
          action: FilledButton(
            onPressed: () => context.go('/dashboard'),
            child: const Text('Back to dashboard'),
          ),
        ),
      ),
    );
  }
}
