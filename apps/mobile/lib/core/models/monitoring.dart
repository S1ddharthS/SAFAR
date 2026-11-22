import 'json.dart';

class WatchItem {
  const WatchItem({
    required this.id,
    required this.activityId,
    required this.field,
    required this.status,
    this.activityName,
    this.rawValue,
    this.lastCheckedAt,
  });

  final String id;
  final String activityId;
  final String field;
  final String status;
  final String? activityName;

  /// Seeded watches store the raw value; newer ones wrap it as `{value: …}`.
  final Object? rawValue;
  final String? lastCheckedAt;

  factory WatchItem.fromJson(Map<String, dynamic> json) => WatchItem(
    id: jsonText(json['id']),
    activityId: jsonText(json['activity_id']),
    field: jsonText(json['field']),
    status: jsonText(json['status'], 'watching'),
    activityName: jsonString(json['activity_name']),
    rawValue: json['last_value'],
    lastCheckedAt: jsonString(json['last_checked_at']),
  );
}

class WatchChange {
  const WatchChange({
    required this.watchId,
    required this.activityId,
    required this.activityName,
    required this.field,
    required this.previous,
    required this.current,
  });

  final String watchId;
  final String activityId;
  final String activityName;
  final String field;
  final Object? previous;
  final Object? current;

  factory WatchChange.fromJson(Map<String, dynamic> json) => WatchChange(
    watchId: jsonText(json['watch_id']),
    activityId: jsonText(json['activity_id']),
    activityName: jsonText(json['activity_name']),
    field: jsonText(json['field']),
    previous: json['previous'],
    current: json['current'],
  );
}

class WatchCheckResult {
  const WatchCheckResult({
    required this.checked,
    required this.changed,
    required this.unchanged,
    required this.note,
  });

  final int checked;
  final List<WatchChange> changed;
  final int unchanged;
  final String note;

  factory WatchCheckResult.fromJson(Map<String, dynamic> json) =>
      WatchCheckResult(
        checked: jsonInt(json['checked']),
        changed: jsonObjects(json['changed'], WatchChange.fromJson),
        unchanged: jsonInt(json['unchanged']),
        note: jsonText(json['note']),
      );
}

class CompanionTarget {
  const CompanionTarget({
    required this.kind,
    required this.id,
    required this.title,
    required this.status,
    this.day,
  });

  final String kind;
  final String id;
  final String title;
  final String status;
  final String? day;

  factory CompanionTarget.fromJson(Map<String, dynamic> json) =>
      CompanionTarget(
        kind: jsonText(json['kind']),
        id: jsonText(json['id']),
        title: jsonText(json['title']),
        status: jsonText(json['status']),
        day: jsonString(json['day']),
      );
}

class CompanionLink {
  const CompanionLink({
    required this.id,
    required this.purpose,
    required this.status,
    required this.expiresAt,
    required this.maxUses,
    required this.usedCount,
    required this.anonymousResponses,
    required this.responseValues,
    required this.createdAt,
    this.target,
  });

  final String id;
  final String purpose;
  final String status;
  final String expiresAt;
  final int maxUses;
  final int usedCount;
  final int anonymousResponses;
  final Map<String, int> responseValues;
  final String createdAt;
  final CompanionTarget? target;

  bool get active => status == 'active';

  factory CompanionLink.fromJson(Map<String, dynamic> json) {
    final target = jsonMap(json['target']);
    final values = <String, int>{};
    jsonMap(json['response_values']).forEach((key, value) {
      values[key] = jsonInt(value);
    });
    return CompanionLink(
      id: jsonText(json['id']),
      purpose: jsonText(json['purpose'], 'vote'),
      status: jsonText(json['status'], 'active'),
      expiresAt: jsonText(json['expires_at']),
      maxUses: jsonInt(json['max_uses'], 1),
      usedCount: jsonInt(json['used_count']),
      anonymousResponses: jsonInt(json['anonymous_responses']),
      responseValues: values,
      createdAt: jsonText(json['created_at']),
      target: target.isEmpty ? null : CompanionTarget.fromJson(target),
    );
  }
}

class CompanionLinkCreated {
  const CompanionLinkCreated({
    required this.link,
    required this.token,
    required this.url,
    required this.disclosure,
  });

  final CompanionLink link;
  final String token;
  final String url;
  final String disclosure;

  factory CompanionLinkCreated.fromJson(Map<String, dynamic> json) =>
      CompanionLinkCreated(
        link: CompanionLink.fromJson(jsonMap(json['link'])),
        token: jsonText(json['token']),
        url: jsonText(json['url']),
        disclosure: jsonText(json['disclosure']),
      );
}

class CompanionResponseItem {
  const CompanionResponseItem({
    required this.id,
    required this.value,
    required this.createdAt,
    this.comment,
  });

  final String id;
  final String value;
  final String createdAt;
  final String? comment;

  factory CompanionResponseItem.fromJson(Map<String, dynamic> json) =>
      CompanionResponseItem(
        id: jsonText(json['id']),
        value: jsonText(json['value']),
        createdAt: jsonText(json['created_at']),
        comment: jsonString(json['comment']),
      );
}

class CompanionResponses {
  const CompanionResponses({
    required this.items,
    required this.anonymous,
    required this.disclosure,
  });

  final List<CompanionResponseItem> items;
  final bool anonymous;
  final String disclosure;

  factory CompanionResponses.fromJson(Map<String, dynamic> json) =>
      CompanionResponses(
        items: jsonObjects(json['items'], CompanionResponseItem.fromJson),
        anonymous: jsonBool(json['anonymous'], true),
        disclosure: jsonText(json['disclosure']),
      );
}

class CompanionPublicTarget {
  const CompanionPublicTarget({
    required this.kind,
    required this.id,
    required this.title,
    required this.status,
    this.summary,
    this.day,
    this.startTime,
    this.registeredVotes = const {},
  });

  final String kind;
  final String id;
  final String title;
  final String status;
  final String? summary;
  final String? day;
  final String? startTime;
  final Map<String, int> registeredVotes;

  factory CompanionPublicTarget.fromJson(Map<String, dynamic> json) {
    final votes = <String, int>{};
    jsonMap(json['registered_votes']).forEach((key, value) {
      votes[key] = jsonInt(value);
    });
    return CompanionPublicTarget(
      kind: jsonText(json['kind']),
      id: jsonText(json['id']),
      title: jsonText(json['title'], 'Decision'),
      status: jsonText(json['status']),
      summary: jsonString(json['summary']),
      day: jsonString(json['day']),
      startTime: jsonString(json['start_time']),
      registeredVotes: votes,
    );
  }
}

class CompanionContext {
  const CompanionContext({
    required this.purpose,
    required this.question,
    required this.options,
    required this.tripName,
    required this.destinationName,
    required this.target,
    required this.expiresAt,
    required this.remainingUses,
    required this.anonymousResponses,
    required this.disclosure,
  });

  final String purpose;
  final String question;
  final List<String> options;
  final String tripName;
  final String destinationName;
  final CompanionPublicTarget target;
  final String expiresAt;
  final int remainingUses;
  final int anonymousResponses;
  final String disclosure;

  factory CompanionContext.fromJson(Map<String, dynamic> json) {
    final trip = jsonMap(json['trip']);
    return CompanionContext(
      purpose: jsonText(json['purpose'], 'vote'),
      question: jsonText(json['question']),
      options: jsonStringList(json['options']),
      tripName: jsonText(trip['name'], 'Journey'),
      destinationName: jsonText(trip['destination_name']),
      target: CompanionPublicTarget.fromJson(jsonMap(json['target'])),
      expiresAt: jsonText(json['expires_at']),
      remainingUses: jsonInt(json['remaining_uses']),
      anonymousResponses: jsonInt(json['anonymous_responses']),
      disclosure: jsonText(json['disclosure']),
    );
  }
}

class GroundResponseItem {
  const GroundResponseItem({
    required this.id,
    required this.observation,
    required this.observedAt,
    required this.confidence,
    required this.verified,
    required this.provenance,
    this.contributorId,
  });

  final String id;
  final String observation;
  final String observedAt;
  final double confidence;
  final bool verified;
  final String provenance;
  final String? contributorId;

  factory GroundResponseItem.fromJson(Map<String, dynamic> json) =>
      GroundResponseItem(
        id: jsonText(json['id']),
        observation: jsonText(json['observation']),
        observedAt: jsonText(json['observed_at']),
        confidence: jsonDouble(json['confidence']),
        verified: jsonBool(json['verified']),
        provenance: jsonText(json['provenance'], 'REPORTED'),
        contributorId: jsonString(json['contributor_id']),
      );
}

class GroundRequestItem {
  const GroundRequestItem({
    required this.id,
    required this.question,
    required this.status,
    required this.createdAt,
    required this.responses,
    this.placeId,
    this.activityId,
  });

  final String id;
  final String question;
  final String status;
  final String createdAt;
  final List<GroundResponseItem> responses;
  final String? placeId;
  final String? activityId;

  factory GroundRequestItem.fromJson(Map<String, dynamic> json) =>
      GroundRequestItem(
        id: jsonText(json['id']),
        question: jsonText(json['question']),
        status: jsonText(json['status'], 'open'),
        createdAt: jsonText(json['created_at']),
        responses: jsonObjects(json['responses'], GroundResponseItem.fromJson),
        placeId: jsonString(json['place_id']),
        activityId: jsonString(json['activity_id']),
      );
}

class OfflinePlace {
  const OfflinePlace({
    required this.name,
    required this.lat,
    required this.lon,
    this.address,
  });

  final String name;
  final double lat;
  final double lon;
  final String? address;

  factory OfflinePlace.fromJson(Map<String, dynamic> json) => OfflinePlace(
    name: jsonText(json['name']),
    lat: jsonDouble(json['lat']),
    lon: jsonDouble(json['lon']),
    address: jsonString(json['address']),
  );
}

class OfflineItem {
  const OfflineItem({
    required this.id,
    required this.day,
    required this.startTime,
    required this.title,
    required this.costEstimate,
    required this.isProtected,
    this.place,
  });

  final String id;
  final String day;
  final String startTime;
  final String title;
  final double costEstimate;
  final bool isProtected;
  final OfflinePlace? place;

  factory OfflineItem.fromJson(Map<String, dynamic> json) {
    final place = jsonMap(json['place']);
    return OfflineItem(
      id: jsonText(json['id']),
      day: jsonText(json['day']),
      startTime: jsonText(json['start_time']),
      title: jsonText(json['title']),
      costEstimate: jsonDouble(json['cost_estimate']),
      isProtected: jsonBool(json['is_protected']),
      place: place.isEmpty ? null : OfflinePlace.fromJson(place),
    );
  }
}

class OfflineMember {
  const OfflineMember({
    required this.id,
    required this.displayName,
    required this.role,
  });

  final String id;
  final String displayName;
  final String role;

  factory OfflineMember.fromJson(Map<String, dynamic> json) => OfflineMember(
    id: jsonText(json['id']),
    displayName: jsonText(json['display_name']),
    role: jsonText(json['role'], 'member'),
  );
}

class OfflinePactBrief {
  const OfflinePactBrief({
    this.mustDo = const [],
    this.flexible = const [],
    this.confirmedTimes = const {},
  });

  final List<String> mustDo;
  final List<String> flexible;
  final Map<String, String> confirmedTimes;

  factory OfflinePactBrief.fromJson(Map<String, dynamic> json) {
    final times = <String, String>{};
    jsonMap(json['confirmed_times']).forEach((key, value) {
      times[key] = jsonText(value);
    });
    return OfflinePactBrief(
      mustDo: jsonStringList(json['must_do']),
      flexible: jsonStringList(json['flexible']),
      confirmedTimes: times,
    );
  }
}

class OfflineTripBrief {
  const OfflineTripBrief({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.currency,
    required this.baseLat,
    required this.baseLon,
    this.destination,
  });

  final String id;
  final String name;
  final String startDate;
  final String endDate;
  final String currency;
  final double baseLat;
  final double baseLon;
  final String? destination;

  factory OfflineTripBrief.fromJson(Map<String, dynamic> json) {
    final base = jsonMap(json['base']);
    return OfflineTripBrief(
      id: jsonText(json['id']),
      name: jsonText(json['name']),
      startDate: jsonText(json['start_date']),
      endDate: jsonText(json['end_date']),
      currency: jsonText(json['currency'], 'EUR'),
      baseLat: jsonDouble(base['lat']),
      baseLon: jsonDouble(base['lon']),
      destination: jsonString(json['destination']),
    );
  }
}

class OfflineSnapshot {
  const OfflineSnapshot({
    required this.generatedAt,
    required this.staleAfter,
    required this.trip,
    required this.confirmedVersion,
    required this.items,
    required this.members,
    required this.disclosure,
    this.pact,
  });

  final String generatedAt;
  final String staleAfter;
  final OfflineTripBrief trip;
  final int confirmedVersion;
  final List<OfflineItem> items;
  final List<OfflineMember> members;
  final String disclosure;
  final OfflinePactBrief? pact;

  bool get stale {
    final expires = DateTime.tryParse(staleAfter);
    if (expires == null) return false;
    // API timestamps are naive UTC; interpret them as such.
    final utc = expires.isUtc
        ? expires
        : DateTime.utc(
            expires.year,
            expires.month,
            expires.day,
            expires.hour,
            expires.minute,
            expires.second,
            expires.millisecond,
            expires.microsecond,
          );
    return DateTime.now().toUtc().isAfter(utc);
  }

  factory OfflineSnapshot.fromJson(Map<String, dynamic> json) {
    final pact = jsonMap(json['pact']);
    return OfflineSnapshot(
      generatedAt: jsonText(json['generated_at']),
      staleAfter: jsonText(json['stale_after']),
      trip: OfflineTripBrief.fromJson(jsonMap(json['trip'])),
      confirmedVersion: jsonInt(json['confirmed_version']),
      items: jsonObjects(json['items'], OfflineItem.fromJson),
      members: jsonObjects(json['members'], OfflineMember.fromJson),
      disclosure: jsonText(json['disclosure']),
      pact: pact.isEmpty ? null : OfflinePactBrief.fromJson(pact),
    );
  }
}

class SyncQueueEntry {
  const SyncQueueEntry({
    required this.clientId,
    required this.operation,
    required this.status,
    this.appliedAt,
    this.createdAt,
  });

  final String clientId;
  final String operation;
  final String status;
  final String? appliedAt;
  final String? createdAt;

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) => SyncQueueEntry(
    clientId: jsonText(json['client_id']),
    operation: jsonText(json['operation']),
    status: jsonText(json['status'], 'pending'),
    appliedAt: jsonString(json['applied_at']),
    createdAt: jsonString(json['created_at']),
  );
}

class SyncItemResult {
  const SyncItemResult({
    required this.clientId,
    required this.status,
    this.id,
    this.reason,
  });

  final String clientId;
  final String status;
  final String? id;
  final String? reason;

  factory SyncItemResult.fromJson(Map<String, dynamic> json) => SyncItemResult(
    clientId: jsonText(json['client_id']),
    status: jsonText(json['status']),
    id: jsonString(json['id']),
    reason: jsonString(json['reason']),
  );
}

class SyncOutcome {
  const SyncOutcome({
    required this.applied,
    required this.skipped,
    required this.rejected,
    required this.results,
    required this.note,
  });

  final int applied;
  final int skipped;
  final int rejected;
  final List<SyncItemResult> results;
  final String note;

  factory SyncOutcome.fromJson(Map<String, dynamic> json) => SyncOutcome(
    applied: jsonInt(json['applied']),
    skipped: jsonInt(json['skipped']),
    rejected: jsonInt(json['rejected']),
    results: jsonObjects(json['results'], SyncItemResult.fromJson),
    note: jsonText(json['note']),
  );
}

class TaskAssigneeSummary {
  const TaskAssigneeSummary({
    required this.userId,
    required this.displayName,
    required this.open,
    required this.done,
    required this.total,
  });

  final String? userId;
  final String displayName;
  final int open;
  final int done;
  final int total;

  factory TaskAssigneeSummary.fromJson(Map<String, dynamic> json) =>
      TaskAssigneeSummary(
        userId: jsonString(json['user_id']),
        displayName: jsonText(json['display_name'], 'Unassigned'),
        open: jsonInt(json['open']),
        done: jsonInt(json['done']),
        total: jsonInt(json['total']),
      );
}

class TaskLoadEntry {
  const TaskLoadEntry({
    required this.key,
    required this.displayName,
    required this.open,
  });

  final String key;
  final String displayName;
  final int open;

  factory TaskLoadEntry.fromJson(Map<String, dynamic> json) => TaskLoadEntry(
    key: jsonText(json['key']),
    displayName: jsonText(json['display_name']),
    open: jsonInt(json['open']),
  );
}

