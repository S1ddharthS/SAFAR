import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/json.dart';
import '../models/safety.dart';
import '../network/api_client.dart';

class SafetyRepository {
  SafetyRepository(this._api);

  final ApiClient _api;

  static const _cachePrefix = 'safar_safety_status_';

  Future<SoloSafetyStatus> getSafetyStatus(String tripId) async {
    try {
      final response = await _api.get('/api/trips/$tripId/safety');
      final map = jsonMap(response);
      final status = SoloSafetyStatus.fromJson(map);

      // Cache offline
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('$_cachePrefix$tripId', jsonEncode(map));
      } catch (_) {
        // Cache failures should not break the online flow
      }

      return status;
    } catch (e) {
      // Offline fallback: check local storage
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('$_cachePrefix$tripId');
        if (cached != null && cached.isNotEmpty) {
          final decoded = jsonDecode(cached);
          if (decoded is Map<String, dynamic>) {
            return SoloSafetyStatus.fromJson(decoded);
          }
        }
      } catch (_) {
        // Ignore cache read errors and rethrow original exception
      }
      rethrow;
    }
  }

  Future<EmergencyContact> addEmergencyContact(
    String tripId, {
    required String name,
    required String relationship,
    required String phone,
    String? email,
    String? notes,
    bool isPrimary = false,
  }) async {
    final response = await _api.post(
      '/api/trips/$tripId/safety/contacts',
      data: {
        'name': name,
        'relationship': relationship,
        'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'is_primary': isPrimary,
      },
    );
    return EmergencyContact.fromJson(jsonMap(response));
  }

  Future<void> deleteEmergencyContact(String tripId, String contactId) async {
    await _api.delete('/api/trips/$tripId/safety/contacts/$contactId');
  }

  Future<TripCheckIn> recordCheckIn(
    String tripId, {
    String status = 'safe',
    String? locationName,
    double? lat,
    double? lon,
    String? message,
  }) async {
    final response = await _api.post(
      '/api/trips/$tripId/safety/check-in',
      data: {
        'status': status,
        if (locationName != null && locationName.isNotEmpty)
          'location_name': locationName,
        'lat': ?lat,
        'lon': ?lon,
        if (message != null && message.isNotEmpty) 'message': message,
      },
    );
    return TripCheckIn.fromJson(jsonMap(response));
  }

  Future<SoloSafetySettings> updateSettings(
    String tripId, {
    int? checkInFrequencyHours,
    bool? locationSharingEnabled,
  }) async {
    final response = await _api.patch(
      '/api/trips/$tripId/safety/settings',
      data: {
        'check_in_frequency_hours': ?checkInFrequencyHours,
        'location_sharing_enabled': ?locationSharingEnabled,
      },
    );
    return SoloSafetySettings.fromJson(jsonMap(response));
  }
}
