import 'common.dart';
import 'discovery.dart';
import 'json.dart';

class CirclePost {
  const CirclePost({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.author,
    this.activityId,
  });

  final String id;
  final String title;
  final String body;
  final String status;
  final String createdAt;
  final User? author;
  final String? activityId;

  factory CirclePost.fromJson(Map<String, dynamic> json) {
    final authorJson = jsonMap(json['author']);
    return CirclePost(
      id: jsonText(json['id']),
      title: jsonText(json['title']),
      body: jsonText(json['body']),
      status: jsonText(json['status']),
      createdAt: jsonText(json['created_at']),
      author: authorJson.isEmpty ? null : User.fromJson(authorJson),
      activityId: jsonString(json['activity_id']),
    );
  }
}

class Circle {
  const Circle({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.joined,
    this.interests = const [],
    this.createdAt,
  });

  final String id;
  final String slug;
  final String name;
  final String description;
  final int memberCount;
  final bool joined;
  final List<String> interests;
  final String? createdAt;

  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
    id: jsonText(json['id']),
    slug: jsonText(json['slug']),
    name: jsonText(json['name']),
    description: jsonText(json['description']),
    memberCount: jsonInt(json['member_count']),
    joined: jsonBool(json['joined']),
    interests: jsonStringList(json['interests']),
    createdAt: jsonString(json['created_at']),
  );
}

class CircleDetail extends Circle {
  const CircleDetail({
    required super.id,
    required super.slug,
    required super.name,
    required super.description,
    required super.memberCount,
    required super.joined,
    super.interests,
    super.createdAt,
    this.posts = const [],
    this.members = const [],
  });

  final List<CirclePost> posts;
  final List<CircleMember> members;

  factory CircleDetail.fromJson(Map<String, dynamic> json) {
    final base = Circle.fromJson(json);
    return CircleDetail(
      id: base.id,
      slug: base.slug,
      name: base.name,
      description: base.description,
      memberCount: base.memberCount,
      joined: base.joined,
      interests: base.interests,
      createdAt: base.createdAt,
      posts: jsonObjects(json['posts'], CirclePost.fromJson),
      members: jsonObjects(json['members'], CircleMember.fromJson),
    );
  }
}

class CircleMember {
  const CircleMember({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role;

  factory CircleMember.fromJson(Map<String, dynamic> json) => CircleMember(
    userId: jsonText(json['user_id']),
    displayName: jsonText(json['display_name']),
    role: jsonText(json['role'], 'member'),
  );
}

class Contributor {
  const Contributor({
    required this.id,
    required this.bio,
    required this.expertise,
    required this.verified,
    required this.acceptsRequests,
    this.user,
    this.destination,
  });

  final String id;
  final String? bio;
  final List<String> expertise;
  final bool verified;
  final bool acceptsRequests;
  final User? user;
  final Destination? destination;

  factory Contributor.fromJson(Map<String, dynamic> json) {
    final userJson = jsonMap(json['user']);
    final destinationJson = jsonMap(json['destination']);
    return Contributor(
      id: jsonText(json['id']),
      bio: jsonString(json['bio']),
      expertise: jsonStringList(json['expertise']),
      verified: jsonBool(json['verified']),
      acceptsRequests: jsonBool(json['accepts_requests']),
      user: userJson.isEmpty ? null : User.fromJson(userJson),
      destination: destinationJson.isEmpty
          ? null
          : Destination.fromJson(destinationJson),
    );
  }
}

class TravellerMatch {
  const TravellerMatch({
    required this.id,
    required this.displayName,
    required this.score,
    required this.reasons,
    required this.sharedInterests,
    required this.privacy,
    this.headline,
    this.homeCity,
  });

  final String id;
  final String displayName;
  final double score;
  final List<String> reasons;
  final List<String> sharedInterests;
  final String privacy;
  final String? headline;
  final String? homeCity;

  factory TravellerMatch.fromJson(Map<String, dynamic> json) {
    final user = jsonMap(json['user']);
    return TravellerMatch(
      id: jsonText(user['id']),
      displayName: jsonText(user['display_name']),
      score: jsonDouble(json['score']),
      reasons: jsonStringList(json['reasons']),
      sharedInterests: jsonStringList(json['shared_interests']),
      privacy: jsonText(json['privacy']),
      headline: jsonString(user['headline']),
      homeCity: jsonString(user['home_city']),
    );
  }
}

class SerendipityFeed {
  const SerendipityFeed({
    required this.eligible,
    required this.matches,
    required this.disclosure,
    this.message,
  });

  final bool eligible;
  final List<TravellerMatch> matches;
  final String disclosure;
  final String? message;

  factory SerendipityFeed.fromJson(Map<String, dynamic> json) =>
      SerendipityFeed(
        eligible: jsonBool(json['eligible']),
        matches: jsonObjects(json['matches'], TravellerMatch.fromJson),
        disclosure: jsonText(json['disclosure']),
        message: jsonString(json['message']),
      );
}

class ConnectionUser {
  const ConnectionUser({required this.id, required this.displayName});

  final String id;
  final String displayName;

  factory ConnectionUser.fromJson(Map<String, dynamic> json) => ConnectionUser(
    id: jsonText(json['id']),
    displayName: jsonText(json['display_name']),
  );
}

class ConnectionRequestItem {
  const ConnectionRequestItem({
    required this.id,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.fromUser,
    this.toUser,
    this.message,
  });

  final String id;
  final String direction;
  final String status;
  final String createdAt;
  final ConnectionUser? fromUser;
  final ConnectionUser? toUser;
  final String? message;

  factory ConnectionRequestItem.fromJson(Map<String, dynamic> json) {
    final from = jsonMap(json['from_user']);
    final to = jsonMap(json['to_user']);
    return ConnectionRequestItem(
      id: jsonText(json['id']),
      direction: jsonText(json['direction'], 'incoming'),
      status: jsonText(json['status'], 'pending'),
      createdAt: jsonText(json['created_at']),
      fromUser: from.isEmpty ? null : ConnectionUser.fromJson(from),
      toUser: to.isEmpty ? null : ConnectionUser.fromJson(to),
      message: jsonString(json['message']),
    );
  }
}

class ThreadResponse {
  const ThreadResponse({
    required this.completedTrips,
    required this.traditions,
    required this.note,
  });

  final int completedTrips;
  final List<ThreadTradition> traditions;
  final String note;

  factory ThreadResponse.fromJson(Map<String, dynamic> json) => ThreadResponse(
    completedTrips: jsonInt(json['completed_trips']),
    traditions: jsonObjects(json['traditions'], ThreadTradition.fromJson),
    note: jsonText(json['note']),
  );
}

class ThreadTradition {
  const ThreadTradition({
    required this.activityId,
    required this.name,
    required this.priceEstimate,
    required this.durationMinutes,
    required this.sentiments,
  });

  final String activityId;
  final String name;
  final double priceEstimate;
  final int durationMinutes;
  final List<String> sentiments;

  factory ThreadTradition.fromJson(Map<String, dynamic> json) =>
      ThreadTradition(
        activityId: jsonText(json['activity_id']),
        name: jsonText(json['name']),
        priceEstimate: jsonDouble(json['price_estimate']),
        durationMinutes: jsonInt(json['duration_minutes']),
        sentiments: jsonStringList(json['sentiments']),
      );
}

class PlaceReportItem {
  const PlaceReportItem({
    required this.id,
    required this.category,
    required this.value,
    required this.observedAt,
    required this.provenance,
    required this.verified,
    required this.helpfulCount,
    this.note,
    this.freshnessLabel,
    this.reporter,
    this.isMine = false,
  });

  final String id;
  final String category;
  final Map<String, dynamic> value;
  final String observedAt;
  final String provenance;
  final bool verified;
  final int helpfulCount;
  final String? note;
  final String? freshnessLabel;
  final User? reporter;
  final bool isMine;

  factory PlaceReportItem.fromJson(Map<String, dynamic> json) {
    final reporterJson = jsonMap(json['reporter']);
    return PlaceReportItem(
      id: jsonText(json['id']),
      category: jsonText(json['category']),
      value: jsonMap(json['value']),
      observedAt: jsonText(json['observed_at']),
      provenance: jsonText(json['provenance'], 'REPORTED'),
      verified: jsonBool(json['verified']),
      helpfulCount: jsonInt(json['helpful_count']),
      note: jsonString(json['note']),
      freshnessLabel: jsonString(json['freshness_label']),
      reporter: reporterJson.isEmpty ? null : User.fromJson(reporterJson),
      isMine: jsonBool(json['is_mine']),
    );
  }
}
