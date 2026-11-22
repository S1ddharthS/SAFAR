// Phase 13 Step 4: Flutter Widget UI & Accessibility Experience Tests
// Validates UI rendering, light/dark themes, and 150% text scale.
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

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  group('Phase 13 Step 4: Flutter Widget UI & Accessibility Experience', () {
    testWidgets('TripOverviewScreen renders cleanly in Light and Dark mode', (tester) async {
      _usePhoneViewport(tester);

      final testTrip = Trip(
        id: 'trip-pilot-1',
        name: 'Kyoto Controlled Pilot Voyage',
        destinationName: 'Kyoto, Japan',
        startDate: '2026-10-15',
        endDate: '2026-10-22',
        groupSize: 4,
        currency: 'EUR',
        baseLat: 35.0116,
        baseLon: 135.7681,
        status: 'planning',
        privacy: 'private',
        createdBy: 'user-mira',
        memberCount: 3,
        myRole: 'owner',
      );

      // Render Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-pilot-1').overrideWith((ref) async => testTrip),
            itineraryProvider('trip-pilot-1').overrideWith(
              (ref) async => const Itinerary(
                itineraryId: 'it-1',
                confirmedVersion: 1,
                myRole: 'owner',
                items: [],
                versions: [],
                openProposals: 0,
                totals: ItineraryTotals(),
              ),
            ),
            membersProvider('trip-pilot-1').overrideWith((ref) async => []),
            engineProvider('trip-pilot-1').overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: SafarTheme.light(),
            home: const TripOverviewScreen(tripId: 'trip-pilot-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kyoto Controlled Pilot Voyage'), findsAtLeastNWidgets(1));
      expect(find.text('KYOTO, JAPAN'), findsOneWidget);

      // Render Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-pilot-1').overrideWith((ref) async => testTrip),
            itineraryProvider('trip-pilot-1').overrideWith(
              (ref) async => const Itinerary(
                itineraryId: 'it-1',
                confirmedVersion: 1,
                myRole: 'owner',
                items: [],
                versions: [],
                openProposals: 0,
                totals: ItineraryTotals(),
              ),
            ),
            membersProvider('trip-pilot-1').overrideWith((ref) async => []),
            engineProvider('trip-pilot-1').overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: SafarTheme.dark(),
            home: const TripOverviewScreen(tripId: 'trip-pilot-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kyoto Controlled Pilot Voyage'), findsAtLeastNWidgets(1));
    });

    testWidgets('ItineraryScreen renders with accessibility large text scale', (tester) async {
      _usePhoneViewport(tester);

      final List<ItineraryItem> items = [
        const ItineraryItem(
          id: 'item-1',
          day: '2026-10-15',
          startTime: '09:00',
          endTime: '12:00',
          title: 'Fushimi Inari Accessible Trail Walk',
          costEstimate: 0.0,
          status: 'confirmed',
          isProtected: true,
          attendance: null,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-pilot-1').overrideWith(
              (ref) async => Trip(
                id: 'trip-pilot-1',
                name: 'Kyoto Trip',
                destinationName: 'Kyoto',
                startDate: '2026-10-15',
                endDate: '2026-10-20',
                groupSize: 4,
                currency: 'EUR',
                baseLat: 35.0116,
                baseLon: 135.7681,
                status: 'planning',
                privacy: 'private',
                createdBy: 'user-mira',
                memberCount: 2,
                myRole: 'owner',
              ),
            ),
            itineraryProvider('trip-pilot-1').overrideWith(
              (ref) async => Itinerary(
                itineraryId: 'it-1',
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
            theme: SafarTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5), // 150% Large text accessibility
              ),
              child: child!,
            ),
            home: const ItineraryScreen(tripId: 'trip-pilot-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Fushimi Inari Accessible Trail Walk'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('ExpensesScreen handles loading and empty states cleanly', (tester) async {
      _usePhoneViewport(tester);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripProvider('trip-pilot-1').overrideWith(
              (ref) async => Trip(
                id: 'trip-pilot-1',
                name: 'Kyoto Trip',
                destinationName: 'Kyoto',
                startDate: '2026-10-15',
                endDate: '2026-10-20',
                groupSize: 4,
                currency: 'EUR',
                baseLat: 35.0116,
                baseLon: 135.7681,
                status: 'planning',
                privacy: 'private',
                createdBy: 'user-mira',
                memberCount: 2,
                myRole: 'owner',
              ),
            ),
            expensesProvider('trip-pilot-1').overrideWith(
              (ref) async => const ExpenseTotals(
                items: [],
                totals: {},
              ),
            ),
            balancesProvider('trip-pilot-1').overrideWith(
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
            home: const ExpensesScreen(tripId: 'trip-pilot-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shared expenses'), findsOneWidget);
      expect(find.text('No shared expenses'), findsOneWidget);
    });

    testWidgets('SettingsScreen renders account & preference controls', (tester) async {
      _usePhoneViewport(tester);

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
                  bio: 'Slow traveler',
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
    });
  });
}
