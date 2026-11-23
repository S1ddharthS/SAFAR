import 'json.dart';

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.name,
    required this.relationship,
    required this.phone,
    this.email,
    this.notes,
    this.isPrimary = false,
    this.createdAt,
  });

  final String id;
  final String tripId;
  final String userId;
  final String name;
  final String relationship;
  final String phone;
  final String? email;
  final String? notes;
  final bool isPrimary;
  final String? createdAt;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: jsonText(json['id']),
        tripId: jsonText(json['trip_id']),
        userId: jsonText(json['user_id']),
        name: jsonText(json['name']),
        relationship: jsonText(json['relationship'], 'Contact'),
        phone: jsonText(json['phone']),
        email: jsonString(json['email']),
        notes: jsonString(json['notes']),
        isPrimary: jsonBool(json['is_primary']),
        createdAt: jsonString(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trip_id': tripId,
        'user_id': userId,
        'name': name,
        'relationship': relationship,
        'phone': phone,
        if (email != null) 'email': email,
        if (notes != null) 'notes': notes,
        'is_primary': isPrimary,
        if (createdAt != null) 'created_at': createdAt,
      };
}

class TripCheckIn {
  const TripCheckIn({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.status,
    this.locationName,
    this.lat,
    this.lon,
    this.message,
    this.createdAt,
  });

  final String id;
  final String tripId;
  final String userId;
  final String status;
  final String? locationName;
  final double? lat;
  final double? lon;
  final String? message;
  final String? createdAt;

  factory TripCheckIn.fromJson(Map<String, dynamic> json) => TripCheckIn(
        id: jsonText(json['id']),
        tripId: jsonText(json['trip_id']),
        userId: jsonText(json['user_id']),
        status: jsonText(json['status'], 'safe'),
        locationName: jsonString(json['location_name']),
        lat: jsonDoubleOrNull(json['lat']),
        lon: jsonDoubleOrNull(json['lon']),
        message: jsonString(json['message']),
        createdAt: jsonString(json['created_at']),
      );
}

class SoloSafetySettings {
  const SoloSafetySettings({
    required this.tripId,
    this.checkInFrequencyHours = 24,
    this.lastCheckInAt,
    this.nextCheckInDue,
    this.locationSharingEnabled = false,
    this.shareToken,
    this.updatedAt,
  });

  final String tripId;
  final int checkInFrequencyHours;
  final String? lastCheckInAt;
  final String? nextCheckInDue;
  final bool locationSharingEnabled;
  final String? shareToken;
  final String? updatedAt;

  factory SoloSafetySettings.fromJson(Map<String, dynamic> json) =>
      SoloSafetySettings(
        tripId: jsonText(json['trip_id']),
        checkInFrequencyHours: jsonInt(json['check_in_frequency_hours'], 24),
        lastCheckInAt: jsonString(json['last_check_in_at']),
        nextCheckInDue: jsonString(json['next_check_in_due']),
        locationSharingEnabled: jsonBool(json['location_sharing_enabled']),
        shareToken: jsonString(json['share_token']),
        updatedAt: jsonString(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'check_in_frequency_hours': checkInFrequencyHours,
        if (lastCheckInAt != null) 'last_check_in_at': lastCheckInAt,
        if (nextCheckInDue != null) 'next_check_in_due': nextCheckInDue,
        'location_sharing_enabled': locationSharingEnabled,
        if (shareToken != null) 'share_token': shareToken,
        if (updatedAt != null) 'updated_at': updatedAt,
      };
}

class LocalEmergencyNumbers {
  const LocalEmergencyNumbers({
    required this.countryCode,
    required this.countryName,
    required this.police,
    required this.ambulance,
    required this.fire,
    this.general,
  });

  final String countryCode;
  final String countryName;
  final String police;
  final String ambulance;
  final String fire;
  final String? general;

  factory LocalEmergencyNumbers.fromJson(Map<String, dynamic> json) =>
      LocalEmergencyNumbers(
        countryCode: jsonText(json['country_code'], 'INTL'),
        countryName: jsonText(json['country_name'], 'International'),
        police: jsonText(json['police'], '112'),
        ambulance: jsonText(json['ambulance'], '112'),
        fire: jsonText(json['fire'], '112'),
        general: jsonString(json['general']),
      );

  Map<String, dynamic> toJson() => {
        'country_code': countryCode,
        'country_name': countryName,
        'police': police,
        'ambulance': ambulance,
        'fire': fire,
        if (general != null) 'general': general,
      };
}

class SoloSafetyStatus {
  const SoloSafetyStatus({
    required this.tripId,
    required this.tripName,
    required this.isSolo,
    required this.settings,
    required this.contacts,
    required this.recentCheckIns,
    required this.isOverdue,
    required this.hoursOverdue,
    required this.localEmergencyNumbers,
    this.lastCheckIn,
  });

  final String tripId;
  final String tripName;
  final bool isSolo;
  final SoloSafetySettings settings;
  final List<EmergencyContact> contacts;
  final List<TripCheckIn> recentCheckIns;
  final TripCheckIn? lastCheckIn;
  final bool isOverdue;
  final double hoursOverdue;
  final LocalEmergencyNumbers localEmergencyNumbers;

  factory SoloSafetyStatus.fromJson(Map<String, dynamic> json) {
    final lastCiMap = jsonMap(json['last_check_in']);
    return SoloSafetyStatus(
      tripId: jsonText(json['trip_id']),
      tripName: jsonText(json['trip_name']),
      isSolo: jsonBool(json['is_solo'], true),
      settings: SoloSafetySettings.fromJson(jsonMap(json['settings'])),
      contacts: jsonObjects(json['contacts'], EmergencyContact.fromJson),
      recentCheckIns: jsonObjects(json['recent_check_ins'], TripCheckIn.fromJson),
      lastCheckIn: lastCiMap.isEmpty ? null : TripCheckIn.fromJson(lastCiMap),
      isOverdue: jsonBool(json['is_overdue']),
      hoursOverdue: jsonDouble(json['hours_overdue']),
      localEmergencyNumbers:
          LocalEmergencyNumbers.fromJson(jsonMap(json['local_emergency_numbers'])),
    );
  }
}
