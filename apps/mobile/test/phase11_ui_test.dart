import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/models/common.dart';
import 'package:safar_mobile/core/models/expenses.dart';
import 'package:safar_mobile/core/models/itinerary.dart';
import 'package:safar_mobile/core/models/memories.dart';
import 'package:safar_mobile/core/models/monitoring.dart';
import 'package:safar_mobile/core/models/social.dart';
import 'package:safar_mobile/core/models/trip.dart';
import 'package:safar_mobile/core/providers.dart';
import 'package:safar_mobile/core/theme/safar_theme.dart';
import 'package:safar_mobile/core/widgets/safar_widgets.dart';
import 'package:safar_mobile/features/home/dashboard_screen.dart';
import 'package:safar_mobile/features/trip/circles_screen.dart';
import 'package:safar_mobile/features/trip/ground_screen.dart';
import 'package:safar_mobile/features/trip/members_screen.dart';
import 'package:safar_mobile/features/trip/memories_screen.dart';
import 'package:safar_mobile/features/trip/trip_overview_screen.dart';
import 'package:safar_mobile/features/trip/watch_screen.dart';

const _tripId = 'trip-kyoto';

Trip _trip() => const Trip(
  id: _tripId,
  name: 'Kyoto in Slow Bloom',
  destinationName: 'Kyoto, Japan',
  startDate: '2026-12-01',
  endDate: '2026-12-05',
  groupSize: 2,
  currency: 'EUR',
  baseLat: 35.0116,
  baseLon: 135.7681,
  status: 'planning',
  privacy: 'private',
  createdBy: 'u-mira',
  memberCount: 3,
  myRole: 'owner',
);

User _user(String id, String name, String email) =>
    User(id: id, email: email, displayName: name, isAdmin: false);

Member _member({
  required String id,
  required String name,
  required String role,
  bool isSelf = false,
}) => Member(
  id: id,
  displayName: name,
  role: role,
  status: 'active',
  joinedAt: '2026-11-01T09:00:00',
  isSelf: isSelf,
  user: _user('u-$id', name, '$id@safar.demo'),
);

const _itinerary = Itinerary(
  itineraryId: 'it-1',
  confirmedVersion: 1,
  myRole: 'owner',
  items: [],
  versions: [],
  openProposals: 0,
  totals: ItineraryTotals(),
);

const _expenses = ExpenseTotals(items: [], totals: {});

void _smallScreen(WidgetTester tester, {double height = 2400}) {
  tester.view.physicalSize = Size(960, height);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _app(
  Widget home, {
  required List<Override> overrides,
  double textScale = 1.3,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: SafarTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  ),
);

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold()));
  await tester.pump();
}

void main() {
  group('trip overview itinerary states', () {
    testWidgets('does not claim the plan is empty while it is loading', (
      tester,
    ) async {
      _smallScreen(tester);
      final pending = Completer<Itinerary>();
      await tester.pumpWidget(
        _app(
          const TripOverviewScreen(tripId: _tripId),
          overrides: [
            tripProvider.overrideWith((ref, id) async => _trip()),
            membersProvider.overrideWith((ref, id) async => <Member>[]),
            itineraryProvider.overrideWith((ref, id) => pending.future),
            engineProvider.overrideWith((ref, id) async => null),
            expensesProvider.overrideWith((ref, id) async => _expenses),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Nothing confirmed yet'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SkeletonBox && widget.height == 148,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await _dispose(tester);
    });

    testWidgets('shows a retry affordance when the plan fails to load', (
      tester,
    ) async {
      _smallScreen(tester);
      await tester.pumpWidget(
        _app(
          const TripOverviewScreen(tripId: _tripId),
          overrides: [
            tripProvider.overrideWith((ref, id) async => _trip()),
            membersProvider.overrideWith((ref, id) async => <Member>[]),
            itineraryProvider.overrideWith(
              (ref, id) => Future<Itinerary>.error(StateError('offline')),
            ),
            engineProvider.overrideWith((ref, id) async => null),
            expensesProvider.overrideWith((ref, id) async => _expenses),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Itinerary could not be loaded'), findsOneWidget);
      expect(find.text('Nothing confirmed yet'), findsNothing);
      expect(tester.takeException(), isNull);

      await _dispose(tester);
    });
  });

  testWidgets('ground responses wrap at a small width and large text', (
    tester,
  ) async {
    _smallScreen(tester);
    await tester.pumpWidget(
      _app(
        const GroundScreen(tripId: _tripId),
        overrides: [
          groundRequestsProvider.overrideWith(
            (ref, id) async => const [
              GroundRequestItem(
                id: 'gr-1',
                question:
                    'Is the west entrance of the temple open after sunset in '
                    'late November?',
                status: 'open',
                createdAt: '2026-11-19T10:00:00',
                responses: [
                  GroundResponseItem(
                    id: 'resp-1',
                    observation:
                        'The west gate closes at 19:00 and the east gate stays '
                        'open until 21:00.',
                    observedAt: '2026-11-19T11:00:00',
                    confidence: 0.82,
                    verified: true,
                    provenance: 'VERIFIED',
                  ),
                ],
              ),
            ],
          ),
          itineraryProvider.overrideWith((ref, id) async => _itinerary),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('82% confidence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('memories day and card metadata wrap at a small width', (
    tester,
  ) async {
    _smallScreen(tester);
    await tester.pumpWidget(
      _app(
        const MemoriesScreen(tripId: _tripId),
        overrides: [
          memoriesProvider.overrideWith(
            (ref, id) async => const MemoriesResponse(
              total: 2,
              permissions:
                  'Only trip members can see trip memories. Private entries '
                  'are yours alone.',
              days: [
                MemoryDay(
                  date: '2026-11-19',
                  memories: [
                    Memory(
                      id: 'mem-1',
                      userId: 'u-mira',
                      kind: 'text',
                      capturedAt: '2026-11-19T18:30:00',
                      visibility: 'trip',
                      aiGenerated: true,
                      approved: false,
                      lat: 35.0116,
                      lon: 135.7681,
                      textContent:
                          'The light on the water after the rain was the whole '
                          'afternoon, really.',
                    ),
                    Memory(
                      id: 'mem-2',
                      userId: 'u-jonas',
                      kind: 'text',
                      capturedAt: '2026-11-19T20:05:00',
                      visibility: 'trip',
                      aiGenerated: false,
                      approved: true,
                      caption: 'Dinner, second attempt.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 memories'), findsNWidgets(2));
    expect(find.text('AI draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving a circle asks for confirmation first', (tester) async {
    _smallScreen(tester);
    await tester.pumpWidget(
      _app(
        const CirclesScreen(tripId: _tripId),
        overrides: [
          circlesProvider.overrideWith(
            (ref) async => const [
              Circle(
                id: 'c-1',
                slug: 'slow-travel',
                name: 'Slow travel',
                description: 'Long stays, few stops.',
                memberCount: 42,
                joined: true,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Leave Slow travel?'), findsOneWidget);

    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Leave Slow travel?'), findsNothing);
    expect(find.text('Leave'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a watch asks for confirmation first', (tester) async {
    _smallScreen(tester, height: 3600);
    await tester.pumpWidget(
      _app(
        const WatchScreen(tripId: _tripId),
        overrides: [
          watchesProvider.overrideWith(
            (ref, id) async => const [
              WatchItem(
                id: 'w-1',
                activityId: 'act-1',
                field: 'opening_hours',
                status: 'watching',
                activityName: 'Fushimi Inari',
              ),
            ],
          ),
          tripProvider.overrideWith((ref, id) async => _trip()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stop watching'));
    await tester.pumpAndSettle();
    expect(find.text('Stop watching this fact?'), findsOneWidget);

    await tester.tap(find.text('Keep watching'));
    await tester.pumpAndSettle();
    expect(find.text('Stop watching this fact?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid invite emails are rejected before creating a link', (
    tester,
  ) async {
    _smallScreen(tester);
    await tester.pumpWidget(
      _app(
        const MembersScreen(tripId: _tripId),
        overrides: [
          tripProvider.overrideWith((ref, id) async => _trip()),
          membersProvider.overrideWith(
            (ref, id) async => [
              _member(id: 'mira', name: 'Mira Okafor', role: 'owner', isSelf: true),
            ],
          ),
          invitationsProvider.overrideWith((ref, id) async => const []),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Invite someone'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.text('Create invite'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a valid email, or leave it empty for a link.'),
      findsOneWidget,
    );
    expect(find.text('Create invite'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard profile avatar has a 48dp tap target', (
    tester,
  ) async {
    _smallScreen(tester);
    final semanticsHandle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const DashboardScreen(),
        textScale: 1,
        overrides: [
          meProvider.overrideWith(
            (ref) async => Me(
              user: _user('u-mira', 'Mira Okafor', 'mira@safar.demo'),
              profile: const Profile(locationSharing: false),
              dna: const Dna(),
              consents: const {},
              policyVersion: '2026-01',
            ),
          ),
          tripsProvider.overrideWith((ref) async => const <Trip>[]),
          notificationsProvider.overrideWith(
            (ref) async => const NotificationFeed(unread: 0, items: []),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.bySemanticsLabel(RegExp('Your profile')), findsOneWidget);
    final avatarTarget = find
        .ancestor(
          of: find.byType(SafarAvatar),
          matching: find.byType(GestureDetector),
        )
        .first;
    expect(tester.getSize(avatarTarget), const Size(48, 48));

    await _dispose(tester);
    semanticsHandle.dispose();
  });
}
