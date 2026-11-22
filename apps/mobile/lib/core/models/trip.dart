import 'common.dart';
import 'json.dart';
import 'monitoring.dart';

class NextAction {
  const NextAction({
    required this.title,
    required this.reason,
    required this.href,
    required this.kind,
    this.quietMode = false,
  });

  final String title;
  final String reason;
  final String href;
  final String kind;
  final bool quietMode;

  factory NextAction.fromJson(Map<String, dynamic> json) => NextAction(
    title: jsonText(json['title']),
    reason: jsonText(json['reason']),
    href: jsonText(json['href']),
    kind: jsonText(json['kind'], 'next'),
    quietMode: jsonBool(json['quiet_mode']),
  );
}

class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.destinationName,
    required this.startDate,
    required this.endDate,
    required this.groupSize,
    required this.currency,
    required this.baseLat,
    required this.baseLon,
    required this.status,
    required this.privacy,
    required this.createdBy,
    this.description,
    this.destinationId,
    this.budgetTotal,
    this.memberCount = 0,
    this.myRole = 'member',
    this.createdAt,
    this.nextAction,
  });

  final String id;
  final String name;
  final String destinationName;
  final String startDate;
  final String endDate;
  final int groupSize;
  final String currency;
  final double baseLat;
  final double baseLon;
  final String status;
  final String privacy;
  final String createdBy;
  final String? description;
  final String? destinationId;
  final double? budgetTotal;
  final int memberCount;
  final String myRole;
  final String? createdAt;
  final NextAction? nextAction;

  bool get isOwner => myRole == 'owner';
  bool get canManage => myRole == 'owner' || myRole == 'admin';

  String get dateRangeLabel {
    final start = shortDate(startDate);
    final end = shortDate(endDate);
    if (start == null || end == null) return '$startDate → $endDate';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final startLabel = '${months[start.month - 1]} ${start.day}';
    final endLabel = end.year == start.year
        ? '${months[end.month - 1]} ${end.day}'
        : '${months[end.month - 1]} ${end.day}, ${end.year}';
    return '$startLabel → $endLabel';
  }

  int get dayCount {
    final start = shortDate(startDate);
    final end = shortDate(endDate);
    if (start == null || end == null) return 1;
    final days = end.difference(start).inDays + 1;
    return days < 1 ? 1 : days;
  }

  factory Trip.fromJson(Map<String, dynamic> json) {
    final next = jsonMap(json['next_action']);
    return Trip(
      id: jsonText(json['id']),
      name: jsonText(json['name'], 'Untitled trip'),
      destinationName: jsonText(
        json['destination_name'],
        jsonText(jsonMap(json['destination'])['name'], 'Destination'),
      ),
      startDate: jsonText(json['start_date']),
      endDate: jsonText(json['end_date']),
      groupSize: jsonInt(json['group_size'], 2),
      currency: jsonText(json['currency'], 'EUR'),
      baseLat: jsonDouble(json['base_lat']),
      baseLon: jsonDouble(json['base_lon']),
      status: jsonText(json['status'], 'planning'),
      privacy: jsonText(json['privacy'], 'private'),
      createdBy: jsonText(json['created_by']),
      description: jsonString(json['description']),
      destinationId: jsonString(json['destination_id']),
      budgetTotal: jsonDoubleOrNull(json['budget_total']),
      memberCount: jsonInt(json['member_count'], 1),
      myRole: jsonText(json['my_role'], 'member'),
      createdAt: jsonString(json['created_at']),
      nextAction: next.isEmpty ? null : NextAction.fromJson(next),
    );
  }
}

class Member {
  const Member({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
    required this.joinedAt,
    required this.isSelf,
    this.user,
    this.budgetLimit,
    this.accessibilityNeeds = const [],
  });

  final String id;
  final String displayName;
  final String role;
  final String status;
  final String joinedAt;
  final bool isSelf;
  final User? user;
  final double? budgetLimit;
  final List<String> accessibilityNeeds;

  factory Member.fromJson(Map<String, dynamic> json) {
    final userJson = jsonMap(json['user']);
    return Member(
      id: jsonText(json['id']),
      displayName: jsonText(json['display_name'], 'Member'),
      role: jsonText(json['role'], 'member'),
      status: jsonText(json['status'], 'active'),
      joinedAt: jsonText(json['joined_at']),
      isSelf: jsonBool(json['is_self']),
      user: userJson.isEmpty ? null : User.fromJson(userJson),
      budgetLimit: jsonDoubleOrNull(json['budget_limit']),
      accessibilityNeeds: jsonStringList(json['accessibility_needs']),
    );
  }
}

class Pact {
  const Pact({
    required this.id,
    this.mustDo = const [],
    this.flexible = const [],
    this.individualLimits = const {},
    this.confirmedTimes = const {},
    this.exceptions = const [],
    this.updatedAt,
  });

  final String id;
  final List<String> mustDo;
  final List<String> flexible;
  final Map<String, dynamic> individualLimits;
  final Map<String, String> confirmedTimes;
  final List<String> exceptions;
  final String? updatedAt;

  factory Pact.fromJson(Map<String, dynamic> json) {
    final times = <String, String>{};
    jsonMap(json['confirmed_times']).forEach((key, value) {
      times[key] = jsonText(value);
    });
    return Pact(
      id: jsonText(json['id']),
      mustDo: jsonStringList(json['must_do']),
      flexible: jsonStringList(json['flexible']),
      individualLimits: jsonMap(json['individual_limits']),
      confirmedTimes: times,
      exceptions: jsonStringList(json['exceptions']),
      updatedAt: jsonString(json['updated_at']),
    );
  }
}

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.status,
    this.description,
    this.assigneeId,
    this.createdAt,
  });

  final String id;
  final String title;
  final String status;
  final String? description;
  final String? assigneeId;
  final String? createdAt;

  bool get done => status == 'done';

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    id: jsonText(json['id']),
    title: jsonText(json['title']),
    status: jsonText(json['status'], 'open'),
    description: jsonString(json['description']),
    assigneeId: jsonString(json['assignee_id']),
    createdAt: jsonString(json['created_at']),
  );
}

class TaskSummary {
  const TaskSummary({
    this.open = 0,
    this.done = 0,
    this.total = 0,
    this.byAssignee = const [],
    this.unassigned,
    this.load = const [],
    this.disclosure,
  });

  final int open;
  final int done;
  final int total;
  final List<TaskAssigneeSummary> byAssignee;
  final TaskAssigneeSummary? unassigned;
  final List<TaskLoadEntry> load;
  final String? disclosure;

  factory TaskSummary.fromJson(Map<String, dynamic> json) {
    final totals = jsonMap(json['totals']);
    final unassigned = jsonMap(json['unassigned']);
    return TaskSummary(
      open: jsonInt(totals['open']),
      done: jsonInt(totals['done']),
      total: jsonInt(totals['total']),
      byAssignee: jsonList(json['by_assignee'])
          .map((item) => jsonMap(item))
          .map(TaskAssigneeSummary.fromJson)
          .toList(),
      unassigned: unassigned.isEmpty
          ? null
          : TaskAssigneeSummary.fromJson(unassigned),
      load: jsonObjects(json['load'], TaskLoadEntry.fromJson),
      disclosure: jsonString(json['disclosure']),
    );
  }
}

class Branch {
  const Branch({
    required this.id,
    required this.name,
    required this.status,
    this.memberIds = const [],
    this.activityId,
    this.reunionAt,
    this.reunionPlace,
  });

  final String id;
  final String name;
  final String status;
  final List<String> memberIds;
  final String? activityId;
  final String? reunionAt;
  final String? reunionPlace;

  factory Branch.fromJson(Map<String, dynamic> json) => Branch(
    id: jsonText(json['id']),
    name: jsonText(json['name']),
    status: jsonText(json['status'], 'open'),
    memberIds: jsonStringList(json['member_ids']),
    activityId: jsonString(json['activity_id']),
    reunionAt: jsonString(json['reunion_at']),
    reunionPlace: jsonString(json['reunion_place']),
  );
}

class MissionConstraints {
  const MissionConstraints({
    this.maxCost,
    this.maxEffort,
    this.tag,
    this.respectAccessibility = true,
    this.optional = true,
    this.suggestedActivity,
  });

  final double? maxCost;
  final int? maxEffort;
  final String? tag;
  final bool respectAccessibility;
  final bool optional;
  final String? suggestedActivity;

  factory MissionConstraints.fromJson(Map<String, dynamic> json) =>
      MissionConstraints(
        maxCost: jsonDoubleOrNull(json['max_cost']),
        maxEffort: jsonIntOrNull(json['max_effort']),
        tag: jsonString(json['tag']),
        respectAccessibility: jsonBool(json['respect_accessibility'], true),
        optional: jsonBool(json['optional'], true),
        suggestedActivity: jsonString(json['suggested_activity']),
      );
}

class Mission {
  const Mission({
    required this.id,
    required this.title,
    required this.description,
    this.constraints,
    this.status = 'active',
    this.myStatus,
    this.optional = true,
    this.selfReported = true,
  });

  final String id;
  final String title;
  final String description;
  final MissionConstraints? constraints;
  final String status;
  final String? myStatus;
  final bool optional;
  final bool selfReported;

  bool get completed => myStatus == 'completed';

  factory Mission.fromJson(Map<String, dynamic> json) {
    final constraints = jsonMap(json['constraints']);
    return Mission(
      id: jsonText(json['id']),
      title: jsonText(json['title']),
      description: jsonText(json['description']),
      constraints: constraints.isEmpty
          ? null
          : MissionConstraints.fromJson(constraints),
      status: jsonText(json['status'], 'active'),
      myStatus: jsonString(json['my_status']),
      optional: jsonBool(json['optional'], true),
      selfReported: jsonBool(json['self_reported'], true),
    );
  }
}

class TripActivityEvent {
  const TripActivityEvent({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.entityId,
    this.detail = const {},
  });

  final String id;
  final String action;
  final String entityType;
  final String createdAt;
  final String? entityId;
  final Map<String, dynamic> detail;

  factory TripActivityEvent.fromJson(Map<String, dynamic> json) =>
      TripActivityEvent(
        id: jsonText(json['id']),
        action: jsonText(json['action']),
        entityType: jsonText(json['entity_type']),
        createdAt: jsonText(json['created_at']),
        entityId: jsonString(json['entity_id']),
        detail: jsonMap(json['detail']),
      );
}

class Capsule {
  const Capsule({
    required this.id,
    required this.createdAt,
    required this.staleAfter,
    required this.stale,
    this.snapshot = const {},
  });

  final String id;
  final String createdAt;
  final String staleAfter;
  final bool stale;
  final Map<String, dynamic> snapshot;

  factory Capsule.fromJson(Map<String, dynamic> json) => Capsule(
    id: jsonText(json['id']),
    createdAt: jsonText(json['created_at']),
    staleAfter: jsonText(json['stale_after']),
    stale: jsonBool(json['stale']),
    snapshot: jsonMap(json['snapshot']),
  );
}

class Pulse {
  const Pulse({
    required this.id,
    required this.userId,
    required this.pulseDate,
    required this.energy,
    this.interests = const [],
    this.availableMinutes,
    this.budgetComfort = 3,
    this.radiusKm,
    this.activityPrefs = const [],
    this.note,
    this.isSelf = false,
    this.authorName,
  });

  final String id;
  final String userId;
  final String pulseDate;
  final int energy;
  final List<String> interests;
  final int? availableMinutes;
  final int budgetComfort;
  final double? radiusKm;
  final List<String> activityPrefs;
  final String? note;
  final bool isSelf;
  final String? authorName;

  factory Pulse.fromJson(Map<String, dynamic> json) {
    final author = jsonMap(json['author']);
    return Pulse(
      id: jsonText(json['id']),
      userId: jsonText(json['user_id']),
      pulseDate: jsonText(json['pulse_date']),
      energy: jsonInt(json['energy'], 3),
      interests: jsonStringList(json['interests']),
      availableMinutes: jsonIntOrNull(json['available_minutes']),
      budgetComfort: jsonInt(json['budget_comfort'], 3),
      radiusKm: jsonDoubleOrNull(json['radius_km']),
      activityPrefs: jsonStringList(json['activity_prefs']),
      note: jsonString(json['note']),
      isSelf: jsonBool(json['is_self']),
      authorName: jsonString(author['display_name']),
    );
  }
}

class PulseResponse {
  const PulseResponse({
    required this.date,
    required this.items,
    required this.coverageShared,
    required this.coverageMembers,
    required this.privacy,
    this.myPulse,
  });

  final String date;
  final List<Pulse> items;
  final int coverageShared;
  final int coverageMembers;
  final String privacy;
  final Pulse? myPulse;

  factory PulseResponse.fromJson(Map<String, dynamic> json) {
    final coverage = jsonMap(json['coverage']);
    final mine = jsonMap(json['my_pulse']);
    return PulseResponse(
      date: jsonText(json['date']),
      items: jsonObjects(json['items'], Pulse.fromJson),
      coverageShared: jsonInt(coverage['shared']),
      coverageMembers: jsonInt(coverage['members']),
      privacy: jsonText(json['privacy']),
      myPulse: mine.isEmpty ? null : Pulse.fromJson(mine),
    );
  }
}
