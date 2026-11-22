// Phase 13 Step 5: Mobile Usability, Accessibility Scale & Responsive Layout Tests
// Exercises small screen viewport (320x568), landscape (800x400), 200% text scale,
// keyboard insets, and extreme text length rendering without layout overflows.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/models/common.dart';
import 'package:safar_mobile/core/models/expenses.dart';
import 'package:safar_mobile/core/models/itinerary.dart';
import 'package:safar_mobile/core/models/trip.dart';
import 'package:safar_mobile/core/providers.dart';
import 'package:safar_mobile/core/theme/safar_theme.dart';
import 'package:safar_mobile/features/profile/settings_screen.dart';
import 'package:safar_mobile/features/trip/expenses_screen.dart';
import 'package:safar_mobile/features/trip/itinerary_screen.dart';
import 'package:safar_mobile/features/trip/trip_overview_screen.dart';

void main() {
  group('Phase 13 Step 5: Mobile Usability & Responsive Edge Cases', () {
    testWidgets('Small compact screen (320x568) renders TripOverviewScreen without overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 568 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testTrip = Trip(
        id: 'trip-small-1',
        name: 'Compact Kyoto Exploration',
        destinationName: 'Kyoto, Japan',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        groupSize: 2,
        currency: 'EUR',
        baseLat: 35.0116,
        baseLon: 135.7681,
        status: 'planning',
        privacy: 'private',
        createdBy: 'user-mira',
        memberCount: 2,
        myRole: 'owner',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-small-1').overrideWith((ref) async => testTrip),
            itineraryProvider('trip-small-1').overrideWith(
              (ref) async => const Itinerary(
                itineraryId: 'it-small',
                confirmedVersion: 1,
                myRole: 'owner',
                items: [],
                versions: [],
                openProposals: 0,
                totals: ItineraryTotals(),
              ),
            ),
            membersProvider('trip-small-1').overrideWith((ref) async => []),
            engineProvider('trip-small-1').overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: SafarTheme.light(),
            home: const TripOverviewScreen(tripId: 'trip-small-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Compact Kyoto Exploration'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull, reason: 'No RenderFlex overflow on small screen');
    });

    testWidgets('Extreme text scale (200% Accessibility) renders cleanly on ItineraryScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testTrip = Trip(
        id: 'trip-scale-200',
        name: 'Kyoto Voyage',
        destinationName: 'Kyoto, Japan',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        groupSize: 2,
        currency: 'EUR',
        baseLat: 35.0116,
        baseLon: 135.7681,
        status: 'planning',
        privacy: 'private',
        createdBy: 'user-mira',
        memberCount: 2,
        myRole: 'owner',
      );

      final List<ItineraryItem> items = [
        const ItineraryItem(
          id: 'item-200-1',
          day: '2026-11-01',
          startTime: '08:00',
          endTime: '10:30',
          title: 'Philosopher Path Morning Walk With Accessible Strolling Path',
          costEstimate: 0.0,
          status: 'confirmed',
          isProtected: true,
          attendance: null,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-scale-200').overrideWith((ref) async => testTrip),
            itineraryProvider('trip-scale-200').overrideWith(
              (ref) async => Itinerary(
                itineraryId: 'it-scale-200',
                confirmedVersion: 1,
                myRole: 'owner',
                items: items,
                versions: const [],
                openProposals: 0,
                totals: const ItineraryTotals(items: 1, cost: 0.0, perPerson: 0.0, currency: 'EUR'),
              ),
            ),
          ],
          child: MaterialApp(
            theme: SafarTheme.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2.0), // 200% extreme accessibility scale
              ),
              child: child!,
            ),
            home: const ItineraryScreen(tripId: 'trip-scale-200'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Philosopher Path Morning Walk With Accessible Strolling Path'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'No layout overflow under 200% text scale');
    });

    testWidgets('Landscape orientation (800x400) renders ExpensesScreen with scrolling', (tester) async {
      tester.view.physicalSize = const Size(800 * 2.0, 400 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testTrip = Trip(
        id: 'trip-land-1',
        name: 'Landscape View Trip',
        destinationName: 'Kyoto, Japan',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        groupSize: 3,
        currency: 'EUR',
        baseLat: 35.0116,
        baseLon: 135.7681,
        status: 'planning',
        privacy: 'private',
        createdBy: 'user-mira',
        memberCount: 3,
        myRole: 'owner',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-land-1').overrideWith((ref) async => testTrip),
            expensesProvider('trip-land-1').overrideWith(
              (ref) async => const ExpenseTotals(items: [], totals: {}),
            ),
            balancesProvider('trip-land-1').overrideWith(
              (ref) async => const BalancesResponse(
                totalSpent: 0.0,
                currency: 'EUR',
                balances: [],
                settlements: [],
                disclosure: 'Automated settlement',
              ),
            ),
          ],
          child: MaterialApp(
            theme: SafarTheme.light(),
            home: const ExpensesScreen(tripId: 'trip-land-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shared expenses'), findsOneWidget);
      expect(find.text('No shared expenses'), findsOneWidget);
      final err = tester.takeException();
      if (err is FlutterError) {
        debugPrint('EXACT OVERFLOW DETAIL:\n${err.toStringDeep()}');
      }
      expect(err, isNull, reason: 'Landscape orientation renders cleanly');
    });

    testWidgets('Keyboard insets (viewInsets.bottom: 300) do not cause overflow on SettingsScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300.0);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meProvider.overrideWith(
              (ref) async => Me(
                user: const User(
                  id: 'u-mira',
                  email: 'mira@safar.demo',
                  displayName: 'Mira Okafor',
                  isAdmin: false,
                  timezone: 'UTC',
                  locale: 'en',
                ),
                profile: const Profile(
                  bio: 'Slow traveler and cultural enthusiast',
                  accessibilityNeeds: ['step_free'],
                  locationSharing: true,
                ),
                dna: const Dna(),
                consents: const {},
                policyVersion: '2026-01',
              ),
            ),
          ],
          child: MaterialApp(
            theme: SafarTheme.light(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Mira Okafor'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Keyboard visibility does not produce overflow');
    });

    testWidgets('Extreme text lengths and long destination titles wrap cleanly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final longTrip = Trip(
        id: 'trip-extreme-text',
        name: 'A Very Long Voyage Title Exceeding Normal Character Limits For Stress Testing Group Travelers',
        destinationName: 'St. Petersburg - Historic Imperial Cultural Capital of the Eastern Baltic Sea Region',
        startDate: '2026-11-01',
        endDate: '2026-11-15',
        groupSize: 6,
        currency: 'EUR',
        baseLat: 59.9343,
        baseLon: 30.3351,
        status: 'planning',
        privacy: 'private',
        createdBy: 'user-mira',
        memberCount: 5,
        myRole: 'owner',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-extreme-text').overrideWith((ref) async => longTrip),
            itineraryProvider('trip-extreme-text').overrideWith(
              (ref) async => const Itinerary(
                itineraryId: 'it-extreme',
                confirmedVersion: 1,
                myRole: 'owner',
                items: [],
                versions: [],
                openProposals: 0,
                totals: ItineraryTotals(),
              ),
            ),
            membersProvider('trip-extreme-text').overrideWith((ref) async => []),
            engineProvider('trip-extreme-text').overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: SafarTheme.dark(),
            home: const TripOverviewScreen(tripId: 'trip-extreme-text'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A Very Long Voyage Title Exceeding Normal Character Limits For Stress Testing Group Travelers'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull, reason: 'Extreme title length handled cleanly');
    });
  });
}
