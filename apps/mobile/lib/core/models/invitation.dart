import 'json.dart';

/// A single-use trip invitation. The token is a credential: it is only kept in
/// memory here and shared through the platform share sheet, never logged.
class TripInvitation {
  const TripInvitation({
    required this.id,
    required this.role,
    required this.scope,
    this.token = '',
    this.email,
    this.expiresAt,
    this.acceptedAt,
    this.createdAt,
    this.expired = false,
    this.path = '',
  });

  final String id;
  final String role;
  final String scope;
  final String token;
  final String? email;
  final String? expiresAt;
  final String? acceptedAt;
  final String? createdAt;
  final bool expired;
  final String path;

  bool get accepted => acceptedAt != null;
  bool get usable => !accepted && !expired;

  factory TripInvitation.fromJson(Map<String, dynamic> json) => TripInvitation(
    id: jsonText(json['id']),
    role: jsonText(json['role'], 'member'),
    scope: jsonText(json['scope'], 'full'),
    token: jsonText(json['token']),
    email: jsonString(json['email']),
    expiresAt: jsonString(json['expires_at']),
    acceptedAt: jsonString(json['accepted_at']),
    createdAt: jsonString(json['created_at']),
    expired: jsonBool(json['expired']),
    path: jsonText(json['path']),
  );
}

class InvitationPreview {
  const InvitationPreview({
    required this.tripId,
    required this.tripName,
    required this.role,
    required this.scope,
    this.destinationName,
    this.startDate,
    this.endDate,
    this.invitedBy,
    this.expiresAt,
    this.alreadyMember = false,
    this.accepted = false,
    this.emailBound = false,
  });

  final String tripId;
  final String tripName;
  final String role;
  final String scope;
  final String? destinationName;
  final String? startDate;
  final String? endDate;
  final String? invitedBy;
  final String? expiresAt;
  final bool alreadyMember;
  final bool accepted;
  final bool emailBound;

  factory InvitationPreview.fromJson(Map<String, dynamic> json) {
    final trip = jsonMap(json['trip']);
    return InvitationPreview(
      tripId: jsonText(trip['id']),
      tripName: jsonText(trip['name'], 'A SAFAR trip'),
      role: jsonText(json['role'], 'member'),
      scope: jsonText(json['scope'], 'full'),
      destinationName: jsonString(trip['destination_name']),
      startDate: jsonString(trip['start_date']),
      endDate: jsonString(trip['end_date']),
      invitedBy: jsonString(json['invited_by']),
      expiresAt: jsonString(json['expires_at']),
      alreadyMember: jsonBool(json['already_member']),
      accepted: jsonBool(json['accepted']),
      emailBound: jsonBool(json['email_bound']),
    );
  }
}
