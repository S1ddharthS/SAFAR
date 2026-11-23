import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/models/safety.dart';
import 'package:safar_mobile/core/models/trip.dart';
import 'package:safar_mobile/core/providers.dart';
import 'package:safar_mobile/core/repositories/safety_repository.dart';
import 'package:safar_mobile/core/theme/safar_theme.dart';
import 'package:safar_mobile/features/trip/solo_safety_screen.dart';
import 'package:safar_mobile/features/trips/trip_create_screen.dart';

class _FakeSafetyRepository extends Fake implements SafetyRepository {
  SoloSafetyStatus status = const SoloSafetyStatus(
    tripId: 'trip-1',
    tripName: 'Kyoto Solo Walk',
    isSolo: true,
    settings: SoloSafetySettings(
      tripId: 'trip-1',
      checkInFrequencyHours: 24,
      locationSharingEnabled: true,
      shareToken: 'test-token-123',
    ),
    contacts: [
      EmergencyContact(
        id: 'c-1',
        tripId: 'trip-1',
        userId: 'u-1',
        name: 'Elena Vance',
        relationship: 'Sister',
        phone: '+15551234567',
        isPrimary: true,
      ),
    ],
    recentCheckIns: [
      TripCheckIn(
        id: 'ci-1',
        tripId: 'trip-1',
        userId: 'u-1',
        status: 'safe',
        locationName: 'Gion District',
        message: 'Exploring tea houses',
        createdAt: '2026-11-22T10:00:00Z',
      ),
    ],
    lastCheckIn: TripCheckIn(
      id: 'ci-1',
      tripId: 'trip-1',
      userId: 'u-1',
      status: 'safe',
      locationName: 'Gion District',
      message: 'Exploring tea houses',
      createdAt: '2026-11-22T10:00:00Z',
    ),
    isOverdue: false,
    hoursOverdue: 0.0,
    localEmergencyNumbers: LocalEmergencyNumbers(
      countryCode: 'JP',
      countryName: 'Japan',
      police: '110',
      ambulance: '119',
      fire: '119',
    ),
  );

  @override
  Future<SoloSafetyStatus> getSafetyStatus(String tripId) async => status;

  @override
  Future<EmergencyContact> addEmergencyContact(
    String tripId, {
    required String name,
    required String relationship,
    required String phone,
    String? email,
    String? notes,
    bool isPrimary = false,
  }) async {
    final contact = EmergencyContact(
      id: 'c-new',
      tripId: tripId,
      userId: 'u-1',
      name: name,
      relationship: relationship,
      phone: phone,
      email: email,
      notes: notes,
      isPrimary: isPrimary,
    );
    return contact;
  }

  @override
  Future<void> deleteEmergencyContact(String tripId, String contactId) async {}

  @override
  Future<TripCheckIn> recordCheckIn(
    String tripId, {
    String status = 'safe',
    String? locationName,
    double? lat,
    double? lon,
    String? message,
  }) async {
    return TripCheckIn(
      id: 'ci-new',
      tripId: tripId,
      userId: 'u-1',
      status: status,
      locationName: locationName,
      message: message,
    );
  }

  @override
  Future<SoloSafetySettings> updateSettings(
    String tripId, {
    int? checkInFrequencyHours,
    bool? locationSharingEnabled,
  }) async {
    return SoloSafetySettings(
      tripId: tripId,
      checkInFrequencyHours: checkInFrequencyHours ?? 24,
      locationSharingEnabled: locationSharingEnabled ?? true,
      shareToken: 'test-token-123',
    );
  }
}

void main() {
  group('Solo Travel - Models and Serialization', () {
    test('Trip correctly parses solo trip metadata', () {
      final json = {
        'id': 'trip-solo-1',
        'name': 'Tokyo Solo Discovery',
        'destination_name': 'Tokyo, Japan',
        'start_date': '2026-12-01',
        'end_date': '2026-12-08',
        'group_size': 1,
        'currency': 'EUR',
        'base_lat': 35.6762,
        'base_lon': 139.6503,
        'status': 'planning',
        'privacy': 'private',
        'created_by': 'user-123',
        'trip_type': 'solo',
        'member_count': 1,
        'my_role': 'owner',
      };

      final trip = Trip.fromJson(json);
      expect(trip.tripType, 'solo');
      expect(trip.groupSize, 1);
      expect(trip.isSolo, isTrue);
      expect(trip.isGroup, isFalse);
    });

    test('Trip correctly parses default group trip metadata', () {
      final json = {
        'id': 'trip-group-1',
        'name': 'Kyoto Autumn Walk',
        'destination_name': 'Kyoto, Japan',
        'start_date': '2026-11-20',
        'end_date': '2026-11-25',
        'group_size': 4,
        'currency': 'EUR',
        'base_lat': 35.0116,
        'base_lon': 135.7681,
        'status': 'confirmed',
        'privacy': 'private',
        'created_by': 'user-123',
        'member_count': 4,
        'my_role': 'owner',
      };

      final trip = Trip.fromJson(json);
      expect(trip.tripType, 'group');
      expect(trip.groupSize, 4);
      expect(trip.isSolo, isFalse);
      expect(trip.isGroup, isTrue);
    });

    test('EmergencyContact serializes and deserializes correctly', () {
      final contact = const EmergencyContact(
        id: 'ec-1',
        tripId: 'trip-1',
        userId: 'u-1',
        name: 'Sarah Connor',
        relationship: 'Parent',
        phone: '+1 800 555 0199',
        email: 'sarah@example.com',
        notes: 'Call between 9am and 9pm',
        isPrimary: true,
      );

      final map = contact.toJson();
      expect(map['name'], 'Sarah Connor');
      expect(map['phone'], '+1 800 555 0199');
      expect(map['is_primary'], isTrue);

      final restored = EmergencyContact.fromJson(map);
      expect(restored.name, 'Sarah Connor');
      expect(restored.relationship, 'Parent');
      expect(restored.isPrimary, isTrue);
    });

    test('SoloSafetyStatus parses correctly with local emergency numbers', () {
      final json = {
        'trip_id': 'trip-1',
        'trip_name': 'London Solitude',
        'is_solo': true,
        'settings': {
          'trip_id': 'trip-1',
          'check_in_frequency_hours': 12,
          'location_sharing_enabled': true,
          'share_token': 'beacon-abc',
        },
        'contacts': [
          {
            'id': 'c-1',
            'trip_id': 'trip-1',
            'user_id': 'u-1',
            'name': 'Arthur Dent',
            'relationship': 'Friend',
            'phone': '+44 20 7946 0991',
            'is_primary': true,
          }
        ],
        'recent_check_ins': [],
        'last_check_in': null,
        'is_overdue': false,
        'hours_overdue': 0.0,
        'local_emergency_numbers': {
          'country_code': 'GB',
          'country_name': 'United Kingdom',
          'police': '999',
          'ambulance': '999',
          'fire': '999',
          'general': '112',
        },
      };

      final status = SoloSafetyStatus.fromJson(json);
      expect(status.isSolo, isTrue);
      expect(status.settings.checkInFrequencyHours, 12);
      expect(status.localEmergencyNumbers.police, '999');
      expect(status.contacts.length, 1);
      expect(status.contacts.first.name, 'Arthur Dent');
    });
  });

  group('Solo Travel - UI Widgets', () {
    testWidgets('SoloSafetyScreen displays emergency dialers and check-in button',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSafetyRepo = _FakeSafetyRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            safetyRepositoryProvider.overrideWithValue(fakeSafetyRepo),
          ],
          child: MaterialApp(
            theme: SafarTheme.light(),
            home: const SoloSafetyScreen(tripId: 'trip-1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check title and disclaimer banner
      expect(find.text('Solo Safety Centre'), findsOneWidget);
      expect(
        find.textContaining('SAFAR Solo Safety is a personal check-in'),
        findsOneWidget,
      );

      // Check current safety status card
      expect(find.text('CURRENT SAFETY STATUS'), findsOneWidget);
      expect(find.text('Check In Now'), findsOneWidget);

      // Check emergency numbers for Japan (110, 119)
      expect(find.text('Police'), findsOneWidget);
      expect(find.text('110'), findsOneWidget);
      expect(find.text('Ambulance'), findsOneWidget);
      expect(find.text('119'), findsNWidgets(2)); // Ambulance and Fire are 119 in Japan

      // Check primary contact is rendered
      expect(find.text('Elena Vance'), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);

      // Check beacon share button
      expect(find.text('Share Beacon Link'), findsOneWidget);
    });

    testWidgets('TripCreateScreen shows Group and Solo Journey mode selectors',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            destinationsProvider.overrideWith((ref) => Future.value([])),
          ],
          child: MaterialApp(
            theme: SafarTheme.light(),
            home: const TripCreateScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Both modes present
      expect(find.text('Group Journey'), findsOneWidget);
      expect(find.text('Solo Journey'), findsOneWidget);

      // Group Journey is selected by default
      expect(find.text('Approximate group size'), findsOneWidget);
      expect(find.text('Create trip'), findsOneWidget);

      // Tap Solo Journey
      await tester.tap(find.text('Solo Journey'));
      await tester.pumpAndSettle();

      // Verify Solo mode UI updates
      expect(find.text('Solo Traveller (1 person)'), findsOneWidget);
      expect(find.text('Personal budget (optional)'), findsOneWidget);
      expect(find.text('Create solo trip'), findsOneWidget);
    });
  });
}
