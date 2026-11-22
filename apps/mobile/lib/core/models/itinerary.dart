import 'common.dart';
import 'discovery.dart';
import 'json.dart';

class ItineraryAttendance {
  const ItineraryAttendance({
    this.inCount = 0,
    this.outCount = 0,
    this.joinLaterCount = 0,
    this.myStatus,
  });

  final int inCount;
  final int outCount;
  final int joinLaterCount;
  final String? myStatus;

  factory ItineraryAttendance.fromJson(Map<String, dynamic> json) =>
      ItineraryAttendance(
        inCount: jsonInt(json['in']),
        outCount: jsonInt(json['out']),
        joinLaterCount: jsonInt(json['join_later']),
        myStatus: jsonString(json['my_status']),
      );
}

class ItineraryItem {
  const ItineraryItem({
    required this.id,
    required this.day,
    required this.startTime,
    required this.title,
    required this.costEstimate,
    required this.status,
    required this.isProtected,
    this.endTime,
    this.activityId,
    this.placeId,
    this.notes,
    this.sortOrder = 0,
    this.activity,
    this.attendance,
  });

  final String id;
  final String day;
  final String startTime;
  final String title;
  final double costEstimate;
  final String status;
  final bool isProtected;
  final String? endTime;
  final String? activityId;
  final String? placeId;
  final String? notes;
  final int sortOrder;
  final Activity? activity;
  final ItineraryAttendance? attendance;

  bool get cancelled => status == 'cancelled';

  factory ItineraryItem.fromJson(Map<String, dynamic> json) {
    final activityJson = jsonMap(json['activity']);
    final attendanceJson = jsonMap(json['attendance']);
    return ItineraryItem(
      id: jsonText(json['id']),
      day: jsonText(json['day']),
      startTime: jsonText(json['start_time'], '09:00'),
      title: jsonText(json['title'], 'Untitled'),
      costEstimate: jsonDouble(json['cost_estimate']),
      status: jsonText(json['status'], 'confirmed'),
      isProtected: jsonBool(json['is_protected']),
      endTime: jsonString(json['end_time']),
      activityId: jsonString(json['activity_id']),
      placeId: jsonString(json['place_id']),
      notes: jsonString(json['notes']),
      sortOrder: jsonInt(json['sort_order']),
      activity: activityJson.isEmpty ? null : Activity.fromJson(activityJson),
      attendance: attendanceJson.isEmpty
          ? null
          : ItineraryAttendance.fromJson(attendanceJson),
    );
  }
}

class ItineraryTotals {
  const ItineraryTotals({
    this.cost = 0,
    this.currency = 'EUR',
    this.perPerson = 0,
    this.items = 0,
    this.days = 0,
    this.protectedItems = 0,
  });

  final double cost;
  final String currency;
  final double perPerson;
  final int items;
  final int days;
  final int protectedItems;

  factory ItineraryTotals.fromJson(Map<String, dynamic> json) =>
      ItineraryTotals(
        cost: jsonDouble(json['cost']),
        currency: jsonText(json['currency'], 'EUR'),
        perPerson: jsonDouble(json['per_person']),
        items: jsonInt(json['items']),
        days: jsonInt(json['days']),
        protectedItems: jsonInt(json['protected_items']),
      );
}

class ItineraryVersion {
  const ItineraryVersion({
    required this.id,
    required this.version,
    required this.createdAt,
    required this.createdBy,
    this.note,
  });

  final String id;
  final int version;
  final String createdAt;
  final String createdBy;
  final String? note;

  factory ItineraryVersion.fromJson(Map<String, dynamic> json) =>
      ItineraryVersion(
        id: jsonText(json['id']),
        version: jsonInt(json['version']),
        createdAt: jsonText(json['created_at']),
        createdBy: jsonText(json['created_by']),
        note: jsonString(json['note']),
      );
}

class Itinerary {
  const Itinerary({
    required this.itineraryId,
    required this.confirmedVersion,
    required this.myRole,
    required this.items,
    required this.versions,
    required this.openProposals,
    required this.totals,
  });

  final String itineraryId;
  final int confirmedVersion;
  final String myRole;
  final List<ItineraryItem> items;
  final List<ItineraryVersion> versions;
  final int openProposals;
  final ItineraryTotals totals;

  List<ItineraryItem> forDay(String day) =>
      items.where((item) => item.day == day && !item.cancelled).toList();

  factory Itinerary.fromJson(Map<String, dynamic> json) => Itinerary(
    itineraryId: jsonText(json['itinerary_id']),
    confirmedVersion: jsonInt(json['confirmed_version']),
    myRole: jsonText(json['my_role'], 'member'),
    items: jsonObjects(json['items'], ItineraryItem.fromJson),
    versions: jsonObjects(json['versions'], ItineraryVersion.fromJson),
    openProposals: jsonInt(json['open_proposals']),
    totals: ItineraryTotals.fromJson(jsonMap(json['totals'])),
  );
}

class VoteSet {
  const VoteSet({this.yes = 0, this.no = 0, this.abstain = 0});

  final int yes;
  final int no;
  final int abstain;

  int get total => yes + no + abstain;

  factory VoteSet.fromJson(Map<String, dynamic> json) => VoteSet(
    yes: jsonInt(json['yes']),
    no: jsonInt(json['no']),
    abstain: jsonInt(json['abstain']),
  );
}

class ProposalComment {
  const ProposalComment({
    required this.id,
    required this.value,
    required this.comment,
    required this.createdAt,
    this.user,
  });

  final String id;
  final String value;
  final String comment;
  final String createdAt;
  final User? user;

  factory ProposalComment.fromJson(Map<String, dynamic> json) {
    final userJson = jsonMap(json['user']);
    return ProposalComment(
      id: jsonText(json['id']),
      value: jsonText(json['value']),
      comment: jsonText(json['comment']),
      createdAt: jsonText(json['created_at']),
      user: userJson.isEmpty ? null : User.fromJson(userJson),
    );
  }
}

class PactConflict {
  const PactConflict({
    required this.item,
    required this.rule,
    required this.resolution,
  });

  final String item;
  final String rule;
  final String resolution;

  factory PactConflict.fromJson(Map<String, dynamic> json) => PactConflict(
    item: jsonText(json['item']),
    rule: jsonText(json['rule']),
    resolution: jsonText(json['resolution']),
  );
}

class Proposal {
  const Proposal({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.votes,
    required this.voteCount,
    required this.comments,
    this.summary,
    this.payload = const {},
    this.targetDay,
    this.author,
    this.createdAt = '',
    this.myVote,
    this.pactConflicts = const [],
    this.requiresApproval = false,
    this.impact = const {},
  });

  final String id;
  final String kind;
  final String title;
  final String status;
  final VoteSet votes;
  final int voteCount;
  final List<ProposalComment> comments;
  final String? summary;
  final Map<String, dynamic> payload;
  final String? targetDay;
  final User? author;
  final String createdAt;
  final String? myVote;
  final List<PactConflict> pactConflicts;
  final bool requiresApproval;
  final Map<String, dynamic> impact;

  bool get decided => status == 'approved' || status == 'rejected';

  factory Proposal.fromJson(Map<String, dynamic> json) {
    final authorJson = jsonMap(json['author']);
    return Proposal(
      id: jsonText(json['id']),
      kind: jsonText(json['kind'], 'custom'),
      title: jsonText(json['title']),
      status: jsonText(json['status'], 'open'),
      votes: VoteSet.fromJson(jsonMap(json['votes'])),
      voteCount: jsonInt(json['vote_count']),
      comments: jsonObjects(json['comments'], ProposalComment.fromJson),
      summary: jsonString(json['summary']),
      payload: jsonMap(json['payload']),
      targetDay: jsonString(json['target_day']),
      author: authorJson.isEmpty ? null : User.fromJson(authorJson),
      createdAt: jsonText(json['created_at']),
      myVote: jsonString(json['my_vote']),
      pactConflicts: jsonObjects(
        json['pact_conflicts'],
        PactConflict.fromJson,
      ),
      requiresApproval: jsonBool(json['requires_approval']),
      impact: jsonMap(json['impact']),
    );
  }

  CostImpact? get costImpact =>
      impact.isEmpty ? null : CostImpact.fromJson(impact);
}

class ImpactOperation {
  const ImpactOperation({
    required this.op,
    this.title,
    this.day,
    this.startTime,
    this.cost,
  });

  final String op;
  final String? title;
  final String? day;
  final String? startTime;
  final double? cost;

  factory ImpactOperation.fromJson(Map<String, dynamic> json) =>
      ImpactOperation(
        op: jsonText(json['op']),
        title: jsonString(json['title']),
        day: jsonString(json['day']),
        startTime: jsonString(json['start_time']),
        cost: jsonDoubleOrNull(json['cost']),
      );
}

class ImpactConflict {
  const ImpactConflict({
    this.item,
    this.reason,
    this.rule,
    this.resolution,
    this.proposed,
    this.protected = false,
  });

  final String? item;
  final String? reason;
  final String? rule;
  final String? resolution;
  final String? proposed;
  final bool protected;

  String get summary => reason ?? resolution ?? rule ?? 'Potential conflict';

  factory ImpactConflict.fromJson(Map<String, dynamic> json) => ImpactConflict(
    item: jsonString(json['item']),
    reason: jsonString(json['reason']),
    rule: jsonString(json['rule']),
    resolution: jsonString(json['resolution']),
    proposed: jsonString(json['proposed']),
    protected: jsonBool(json['protected']),
  );
}

class CostImpact {
  const CostImpact({
    required this.operations,
    required this.totalDelta,
    required this.perMemberEstimate,
    required this.currency,
    required this.note,
    this.budgetConflicts = const [],
    this.pactConflicts = const [],
    this.scheduleConflicts = const [],
    this.requiresApproval = true,
    this.error,
  });

  final List<ImpactOperation> operations;
  final double totalDelta;
  final double perMemberEstimate;
  final String currency;
  final String note;
  final List<ImpactConflict> budgetConflicts;
  final List<ImpactConflict> pactConflicts;
  final List<ImpactConflict> scheduleConflicts;
  final bool requiresApproval;
  final String? error;

  bool get hasConflicts =>
      budgetConflicts.isNotEmpty ||
      pactConflicts.isNotEmpty ||
      scheduleConflicts.isNotEmpty;

  factory CostImpact.fromJson(Map<String, dynamic> json) {
    final cost = jsonMap(json['cost_impact']);
    return CostImpact(
      operations: jsonObjects(json['operations'], ImpactOperation.fromJson),
      totalDelta: jsonDouble(cost['total_delta']),
      perMemberEstimate: jsonDouble(cost['per_member_estimate']),
      currency: jsonText(cost['currency'], 'EUR'),
      note: jsonText(cost['note']),
      budgetConflicts: jsonObjects(
        json['budget_conflicts'],
        ImpactConflict.fromJson,
      ),
      pactConflicts: jsonObjects(json['pact_conflicts'], ImpactConflict.fromJson),
      scheduleConflicts: jsonObjects(
        json['schedule_conflicts'],
        ImpactConflict.fromJson,
      ),
      requiresApproval: jsonBool(json['requires_approval'], true),
      error: jsonString(json['error']),
    );
  }
}
