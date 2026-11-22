import 'json.dart';

class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isAdmin,
    this.quietMode = false,
    this.locale = 'en',
    this.timezone,
    this.avatarUrl,
    this.createdAt,
  });

  final String id;
  final String email;
  final String displayName;
  final bool isAdmin;
  final bool quietMode;
  final String locale;
  final String? timezone;
  final String? avatarUrl;
  final String? createdAt;

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: jsonText(json['id']),
    email: jsonText(json['email']),
    displayName: jsonText(json['display_name'], 'Traveller'),
    isAdmin: jsonBool(json['is_admin']),
    quietMode: jsonBool(json['quiet_mode']),
    locale: jsonText(json['locale'], 'en'),
    timezone: jsonString(json['timezone']),
    avatarUrl: jsonString(json['avatar_url']),
    createdAt: jsonString(json['created_at']),
  );
}

class Profile {
  const Profile({
    this.headline,
    this.bio,
    this.homeCity,
    this.travelPace,
    this.budgetLevel,
    this.budgetLimit,
    this.interests = const [],
    this.accessibilityNeeds = const [],
    this.dietary = const [],
    this.languages = const [],
    this.publicProfile = false,
    this.allowDiscovery = false,
    this.locationSharing = false,
  });

  final String? headline;
  final String? bio;
  final String? homeCity;
  final String? travelPace;
  final String? budgetLevel;
  final double? budgetLimit;
  final List<String> interests;
  final List<String> accessibilityNeeds;
  final List<String> dietary;
  final List<String> languages;
  final bool publicProfile;
  final bool allowDiscovery;
  final bool locationSharing;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    headline: jsonString(json['headline']),
    bio: jsonString(json['bio']),
    homeCity: jsonString(json['home_city']),
    travelPace: jsonString(json['travel_pace']),
    budgetLevel: jsonString(json['budget_level']),
    budgetLimit: jsonDoubleOrNull(json['budget_limit']),
    interests: jsonStringList(json['interests']),
    accessibilityNeeds: jsonStringList(json['accessibility_needs']),
    dietary: jsonStringList(json['dietary']),
    languages: jsonStringList(json['languages']),
    publicProfile: jsonBool(json['public_profile']),
    allowDiscovery: jsonBool(json['allow_discovery']),
    locationSharing: jsonBool(json['location_sharing']),
  );
}

class Dna {
  const Dna({
    this.scores = const {},
    this.source,
    this.updatedAt,
    this.dimensions = const [],
    this.note,
  });

  final Map<String, double> scores;
  final String? source;
  final String? updatedAt;
  final List<String> dimensions;
  final String? note;

  factory Dna.fromJson(Map<String, dynamic> json) {
    final rawScores = jsonMap(json['scores']);
    return Dna(
      scores: rawScores.map(
        (key, value) => MapEntry(key, jsonDouble(value)),
      ),
      source: jsonString(json['source']),
      updatedAt: jsonString(json['updated_at']),
      dimensions: jsonStringList(json['dimensions']),
      note: jsonString(json['note']),
    );
  }
}

class Consent {
  const Consent({
    required this.granted,
    required this.policyVersion,
    this.updatedAt,
  });

  final bool granted;
  final String policyVersion;
  final String? updatedAt;

  factory Consent.fromJson(Map<String, dynamic> json) => Consent(
    granted: jsonBool(json['granted']),
    policyVersion: jsonText(json['policy_version']),
    updatedAt: jsonString(json['updated_at']),
  );
}

class Me {
  const Me({
    required this.user,
    required this.profile,
    required this.dna,
    required this.consents,
    required this.policyVersion,
  });

  final User user;
  final Profile profile;
  final Dna dna;
  final Map<String, Consent> consents;
  final String policyVersion;

  factory Me.fromJson(Map<String, dynamic> json) {
    final consents = <String, Consent>{};
    jsonMap(json['consents']).forEach((key, value) {
      consents[key] = Consent.fromJson(jsonMap(value));
    });
    return Me(
      user: User.fromJson(jsonMap(json['user'])),
      profile: Profile.fromJson(jsonMap(json['profile'])),
      dna: Dna.fromJson(jsonMap(json['dna'])),
      consents: consents,
      policyVersion: jsonText(json['policy_version']),
    );
  }
}

class NotificationFeed {
  const NotificationFeed({required this.unread, required this.items});

  final int unread;
  final List<NotificationItem> items;

  factory NotificationFeed.fromJson(Map<String, dynamic> json) =>
      NotificationFeed(
        unread: jsonInt(json['unread']),
        items: jsonObjects(json['items'], NotificationItem.fromJson),
      );
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.read,
    required this.createdAt,
    this.tripId,
    this.body,
    this.link,
  });

  final String id;
  final String kind;
  final String title;
  final bool read;
  final String createdAt;
  final String? tripId;
  final String? body;
  final String? link;

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      NotificationItem(
        id: jsonText(json['id']),
        kind: jsonText(json['kind'], 'update'),
        title: jsonText(json['title']),
        read: jsonBool(json['read']),
        createdAt: jsonText(json['created_at']),
        tripId: jsonString(json['trip_id']),
        body: jsonString(json['body']),
        link: jsonString(json['link']),
      );
}
