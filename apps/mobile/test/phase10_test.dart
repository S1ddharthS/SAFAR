import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/models/common.dart';
import 'package:safar_mobile/core/models/discovery.dart';
import 'package:safar_mobile/core/models/invitation.dart';
import 'package:safar_mobile/core/models/itinerary.dart';
import 'package:safar_mobile/core/models/trip.dart';
import 'package:safar_mobile/core/native/map_tiles.dart';
import 'package:safar_mobile/core/providers.dart';
import 'package:safar_mobile/core/theme/safar_theme.dart';
import 'package:safar_mobile/features/trip/members_screen.dart';
import 'package:safar_mobile/features/trip/nearby_screen.dart';

const _tripId = 'trip-kyoto';

Trip _trip({String myRole = 'owner'}) => Trip(
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
  myRole: myRole,
);

User _user(String id, String name, String email) => User(
  id: id,
  email: email,
  displayName: name,
  isAdmin: false,
);

Member _member({
  required String id,
  required String name,
  required String email,
  required String role,
  bool isSelf = false,
}) => Member(
  id: id,
  displayName: name,
  role: role,
  status: 'active',
  joinedAt: '2026-11-01T09:00:00',
  isSelf: isSelf,
  user: _user('u-$id', name, email),
);

final _members = <Member>[
  _member(
    id: 'mira',
    name: 'Mira Okafor',
    email: 'mira@safar.demo',
    role: 'owner',
    isSelf: true,
  ),
  _member(
    id: 'jonas',
    name: 'Jonas Weber',
    email: 'jonas@safar.demo',
    role: 'admin',
  ),
  _member(
    id: 'aiko',
    name: 'Aiko Tanaka',
    email: 'aiko@safar.demo',
    role: 'member',
  ),
];

Widget _peopleApp({
  required Trip trip,
  required List<Member> members,
  List<TripInvitation> invitations = const [],
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    tripProvider.overrideWith((ref, tripId) async => trip),
    membersProvider.overrideWith((ref, tripId) async => members),
    invitationsProvider.overrideWith((ref, tripId) async => invitations),
  ],
  child: MaterialApp(
    theme: SafarTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const MembersScreen(tripId: _tripId),
  ),
);

NearbyItem _nearbyItem({
  required String name,
  required double lat,
  required double lon,
  String category = 'temple',
  double distanceKm = 1.2,
  int travelMinutes = 15,
}) => NearbyItem(
  activity: Activity(
    id: 'act-$name',
    placeId: 'place-$name',
    destinationId: 'dest-kyoto',
    name: name,
    description: 'A quiet stop near the trip base.',
    place: Place(
      id: 'place-$name',
      destinationId: 'dest-kyoto',
      name: name,
      category: category,
      description: 'A quiet stop near the trip base.',
      lat: lat,
      lon: lon,
    ),
  ),
  distanceKm: distanceKm,
  travelMinutes: travelMinutes,
  provenance: 'ESTIMATED',
);

NearbyResponse _nearby({List<NearbyItem>? items}) => NearbyResponse(
  base: const NearbyBase(lat: 35.0116, lon: 135.7681, source: 'shared trip base'),
  radiusKm: 5,
  items: items ?? [_nearbyItem(name: 'Kiyomizu-dera', lat: 34.9949, lon: 135.785)],
  disclosure: 'Schematic distances from the shared trip base.',
);

Widget _mapApp({
  required NearbyResponse response,
  required bool locationSharing,
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    nearbyProvider.overrideWith((ref, query) async => response),
    itineraryProvider.overrideWith(
      (ref, tripId) async => const Itinerary(
        itineraryId: 'it-1',
        confirmedVersion: 1,
        myRole: 'owner',
        items: [],
        versions: [],
        openProposals: 0,
        totals: ItineraryTotals(),
      ),
    ),
    meProvider.overrideWith(
      (ref) async => Me(
        user: _user('u-mira', 'Mira Okafor', 'mira@safar.demo'),
        profile: Profile(locationSharing: locationSharing),
        dna: const Dna(),
        consents: const {},
        policyVersion: '2026-01',
      ),
    ),
  ],
  child: MaterialApp(
    theme: SafarTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const NearbyScreen(tripId: _tripId),
  ),
);

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('map tile configuration', () {
    test('substitutes zoom, tile coordinates and rotating subdomains', () {
      const provider = MapTileProvider(
        urlTemplate: 'https://tiles.example/{z}/{x}/{y}.png?s={s}',
        attribution: '© Example',
        minZoom: 1,
        maxZoom: 18,
        subdomains: ['a', 'b'],
      );
      expect(provider.url(3, 0, 0), 'https://tiles.example/3/0/0.png?s=a');
      expect(provider.url(3, 1, 0), 'https://tiles.example/3/1/0.png?s=b');
    });

    test('falls back to the schematic map when no endpoint is compiled in', () {
      final config = MapTileConfig.fromEnvironment();
      expect(config.hasTiles, isFalse);
      expect(config.note, contains('SAFAR_MAP_TILE_URL'));
    });

    test('a configured provider reports tiles as available', () {
      const config = MapTileConfig(
        provider: MapTileProvider(
          urlTemplate: 'https://tiles.example/{z}/{x}/{y}.png',
          attribution: '© Example',
          minZoom: 2,
          maxZoom: 18,
        ),
      );
      expect(config.hasTiles, isTrue);
      expect(config.note, isNull);
    });
  });

  group('people and invitations (F04)', () {
    testWidgets('owner sees the group, invite action and open invitations', (
      tester,
    ) async {
      await tester.pumpWidget(
        _peopleApp(
          trip: _trip(),
          members: _members,
          invitations: const [
            TripInvitation(
              id: 'inv-1',
              role: 'admin',
              scope: 'full',
              email: 'akiko@example.com',
              expiresAt: '2026-12-01T00:00:00',
              token: 'tok-1',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('People'), findsOneWidget);
      expect(find.byTooltip('Invite someone'), findsOneWidget);
      expect(find.text('THE GROUP'), findsOneWidget);
      expect(find.text('3 travellers · plan sized for 2'), findsOneWidget);
      expect(find.text('Mira Okafor'), findsOneWidget);
      expect(find.text('Jonas Weber'), findsOneWidget);
      expect(find.text('Aiko Tanaka'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Leave'), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('INVITATIONS'), findsOneWidget);
      expect(find.text('Open invites'), findsOneWidget);
      expect(find.text('akiko@example.com'), findsOneWidget);
      expect(
        find.textContaining('Admin · Full plan · expires 2026-12-01'),
        findsOneWidget,
      );
    });

    testWidgets('owner manages other members but not themselves', (
      tester,
    ) async {
      await tester.pumpWidget(_peopleApp(trip: _trip(), members: _members));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Manage Mira Okafor'), findsNothing);
      expect(find.byTooltip('Manage Jonas Weber'), findsOneWidget);
      expect(find.byTooltip('Manage Aiko Tanaka'), findsOneWidget);

      await tester.tap(find.byTooltip('Manage Jonas Weber'));
      await tester.pumpAndSettle();
      expect(find.text('Change role'), findsOneWidget);
      expect(find.text('Remove from trip'), findsOneWidget);

      await tester.tap(find.text('Remove from trip'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Jonas Weber?'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Jonas Weber?'), findsNothing);
    });

    testWidgets('a plain member gets no admin controls and can leave', (
      tester,
    ) async {
      await tester.pumpWidget(
        _peopleApp(
          trip: _trip(myRole: 'member'),
          members: [
            _member(
              id: 'mira',
              name: 'Mira Okafor',
              email: 'mira@safar.demo',
              role: 'owner',
            ),
            _member(
              id: 'aiko',
              name: 'Aiko Tanaka',
              email: 'aiko@safar.demo',
              role: 'member',
              isSelf: true,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Invite someone'), findsNothing);
      expect(find.text('Open invites'), findsNothing);
      expect(find.byTooltip('Manage Mira Okafor'), findsNothing);
      expect(
        find.text(
          'Everyone here sees the shared plan. Private limits and '
          'preferences stay with each member.',
        ),
        findsOneWidget,
      );
      expect(find.text('2 travellers'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
    });

    testWidgets('invite sheet collects role, access and expiry then cancels', (
      tester,
    ) async {
      await tester.pumpWidget(_peopleApp(trip: _trip(), members: _members));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Invite someone'));
      await tester.pumpAndSettle();

      expect(find.text('Email (optional)'), findsOneWidget);
      expect(find.text('Role'), findsOneWidget);
      expect(find.text('Access'), findsOneWidget);
      expect(find.text('Expires'), findsOneWidget);
      expect(find.text('Create invite'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Email (optional)'), findsNothing);
    });
  });

  group('map and nearby (F10)', () {
    testWidgets('renders the schematic map, places and radius controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        _mapApp(response: _nearby(), locationSharing: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Map & nearby'), findsOneWidget);
      expect(find.byTooltip('Use my current location'), findsOneWidget);
      expect(
        find.text(
          'Schematic map. Tile provider not configured for this build '
          '(SAFAR_MAP_TILE_URL).',
        ),
        findsOneWidget,
      );
      for (final label in ['2 km', '5 km', '10 km', '20 km', '35 km']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final category in [
        'All',
        'Museum',
        'Park',
        'Market',
        'Viewpoint',
        'Restaurant',
        'Landmark',
      ]) {
        expect(find.text(category), findsOneWidget);
      }

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('WITHIN 5 KM'), findsOneWidget);
      expect(find.text('1 catalog places'), findsOneWidget);
      expect(find.text('Kiyomizu-dera'), findsOneWidget);
      expect(find.textContaining('1.2 km · ~15 min'), findsOneWidget);
      expect(
        find.text('Schematic distances from the shared trip base.'.toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty state when nothing is in range', (tester) async {
      await tester.pumpWidget(
        _mapApp(response: _nearby(items: []), locationSharing: false),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('WITHIN 5 KM'), findsOneWidget);
      expect(find.text('Nothing found nearby'), findsOneWidget);
      expect(find.text('No catalog places here'), findsOneWidget);
    });

    testWidgets('location stays off until the profile opts in', (tester) async {
      await tester.pumpWidget(
        _mapApp(response: _nearby(), locationSharing: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Use my current location'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Precise location is off. Enable it in Settings → Privacy before '
          'using your position.',
        ),
        findsOneWidget,
      );
      // Still anchored to the shared base; no system permission request.
      expect(find.byTooltip('Use my current location'), findsOneWidget);
      expect(
        find.text(
          'Tap a dot to inspect a place. The ring marks the 5 km search '
          'radius around the shared trip base — never a live member location.',
        ),
        findsOneWidget,
      );
    });
  });

  group('large text on a phone viewport', () {
    testWidgets('people screen lays out at 130% text', (tester) async {
      _usePhoneViewport(tester);

      await tester.pumpWidget(
        _peopleApp(
          trip: _trip(),
          members: _members,
          invitations: const [
            TripInvitation(
              id: 'inv-1',
              role: 'admin',
              scope: 'full',
              email: 'akiko@example.com',
              expiresAt: '2026-12-01T00:00:00',
              token: 'tok-1',
            ),
          ],
          textScale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('People'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('map screen lays out at 130% text', (tester) async {
      _usePhoneViewport(tester);

      await tester.pumpWidget(
        _mapApp(
          response: _nearby(),
          locationSharing: false,
          textScale: 1.3,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Map & nearby'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
