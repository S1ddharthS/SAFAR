import 'json.dart';

class PlanItemMetrics {
  const PlanItemMetrics({
    required this.activityId,
    required this.name,
    required this.cost,
    required this.duration,
    required this.distanceKm,
    required this.travelMinutes,
    required this.eligible,
  });

  final String activityId;
  final String name;
  final double cost;
  final int duration;
  final double distanceKm;
  final int travelMinutes;
  final bool eligible;

  factory PlanItemMetrics.fromJson(Map<String, dynamic> json) =>
      PlanItemMetrics(
        activityId: jsonText(json['activity_id']),
        name: jsonText(json['name']),
        cost: jsonDouble(json['cost']),
        duration: jsonInt(json['duration']),
        distanceKm: jsonDouble(json['distance_km']),
        travelMinutes: jsonInt(json['travel_minutes']),
        eligible: jsonBool(json['eligible'], true),
      );
}

class PlanMetrics {
  const PlanMetrics({
    required this.name,
    required this.totalCost,
    required this.totalDurationMinutes,
    required this.totalTravelMinutes,
    required this.items,
    this.averageGroupFit,
    this.minimumMemberFit,
  });

  final String name;
  final double totalCost;
  final int totalDurationMinutes;
  final int totalTravelMinutes;
  final List<PlanItemMetrics> items;
  final double? averageGroupFit;
  final double? minimumMemberFit;

  factory PlanMetrics.fromJson(Map<String, dynamic> json) => PlanMetrics(
    name: jsonText(json['name']),
    totalCost: jsonDouble(json['total_cost']),
    totalDurationMinutes: jsonInt(json['total_duration_minutes']),
    totalTravelMinutes: jsonInt(json['total_travel_minutes']),
    items: jsonObjects(json['items'], PlanItemMetrics.fromJson),
    averageGroupFit: jsonDoubleOrNull(json['average_group_fit']),
    minimumMemberFit: jsonDoubleOrNull(json['minimum_member_fit']),
  );
}

class PlanActivityRef {
  const PlanActivityRef({required this.activityId, required this.name});

  final String activityId;
  final String name;

  factory PlanActivityRef.fromJson(Map<String, dynamic> json) => PlanActivityRef(
    activityId: jsonText(json['activity_id']),
    name: jsonText(json['name']),
  );
}

class PlanDiff {
  const PlanDiff({
    this.added = const [],
    this.removed = const [],
    this.kept = const [],
  });

  final List<PlanActivityRef> added;
  final List<PlanActivityRef> removed;
  final List<PlanActivityRef> kept;

  bool get isEmpty => added.isEmpty && removed.isEmpty && kept.isEmpty;

  factory PlanDiff.fromJson(Map<String, dynamic> json) => PlanDiff(
    added: jsonObjects(json['added'], PlanActivityRef.fromJson),
    removed: jsonObjects(json['removed'], PlanActivityRef.fromJson),
    kept: jsonObjects(json['kept'], PlanActivityRef.fromJson),
  );
}

class TwinComparison {
  const TwinComparison({
    required this.day,
    required this.confirmedPlan,
    required this.alternativePlan,
    required this.diff,
    required this.tradeOffs,
    required this.requiresApproval,
    required this.disclosure,
    required this.generatedAt,
  });

  final String day;
  final PlanMetrics confirmedPlan;
  final PlanMetrics alternativePlan;
  final PlanDiff diff;
  final List<String> tradeOffs;
  final bool requiresApproval;
  final String disclosure;
  final String generatedAt;

  factory TwinComparison.fromJson(Map<String, dynamic> json) => TwinComparison(
    day: jsonText(json['day']),
    confirmedPlan: PlanMetrics.fromJson(jsonMap(json['confirmed_plan'])),
    alternativePlan: PlanMetrics.fromJson(jsonMap(json['alternative_plan'])),
    diff: PlanDiff.fromJson(jsonMap(json['diff'])),
    tradeOffs: jsonStringList(json['trade_offs']),
    requiresApproval: jsonBool(json['requires_approval'], true),
    disclosure: jsonText(json['disclosure']),
    generatedAt: jsonText(json['generated_at']),
  );
}

class NegotiationOption {
  const NegotiationOption({
    required this.activityId,
    required this.name,
    required this.minimumFit,
    required this.averageFit,
  });

  final String activityId;
  final String name;
  final double minimumFit;
  final double averageFit;

  factory NegotiationOption.fromJson(Map<String, dynamic> json) =>
      NegotiationOption(
        activityId: jsonText(json['activity_id']),
        name: jsonText(json['name']),
        minimumFit: jsonDouble(json['minimum_fit']),
        averageFit: jsonDouble(json['average_fit']),
      );
}

class NegotiationResult {
  const NegotiationResult({
    required this.status,
    required this.tradeOffs,
    this.message,
    this.compromise,
    this.alternative,
    this.whoBenefits,
    this.whoCompromises,
    this.feasible = false,
    this.disclosure,
  });

  final String status;
  final List<String> tradeOffs;
  final String? message;
  final NegotiationOption? compromise;
  final NegotiationOption? alternative;
  final String? whoBenefits;
  final String? whoCompromises;
  final bool feasible;
  final String? disclosure;

  bool get ready => status == 'compromise_ready' && compromise != null;

  factory NegotiationResult.fromJson(Map<String, dynamic> json) {
    final compromise = jsonMap(json['compromise']);
    final alternative = jsonMap(json['alternative']);
    return NegotiationResult(
      status: jsonText(json['status'], 'needs_options'),
      tradeOffs: jsonStringList(json['trade_offs']),
      message: jsonString(json['message']),
      compromise: compromise.isEmpty
          ? null
          : NegotiationOption.fromJson(compromise),
      alternative: alternative.isEmpty
          ? null
          : NegotiationOption.fromJson(alternative),
      whoBenefits: jsonString(json['who_benefits']),
      whoCompromises: jsonString(json['who_compromises']),
      feasible: jsonBool(json['feasible']),
      disclosure: jsonString(json['disclosure']),
    );
  }
}

class ShadowplanItem {
  const ShadowplanItem({
    required this.id,
    required this.itemId,
    required this.backupActivityId,
    required this.readiness,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String itemId;
  final String backupActivityId;
  final Map<String, dynamic> readiness;
  final String? notes;
  final String? createdAt;

  String get readinessStatus => jsonText(readiness['status'], 'unknown');

  factory ShadowplanItem.fromJson(Map<String, dynamic> json) => ShadowplanItem(
    id: jsonText(json['id']),
    itemId: jsonText(json['item_id']),
    backupActivityId: jsonText(json['backup_activity_id']),
    readiness: jsonMap(json['readiness']),
    notes: jsonString(json['notes']),
    createdAt: jsonString(json['created_at']),
  );
}

class OpportunityWindow {
  const OpportunityWindow({
    required this.start,
    required this.end,
    required this.minutes,
  });

  final String start;
  final String end;
  final int minutes;

  factory OpportunityWindow.fromJson(Map<String, dynamic> json) =>
      OpportunityWindow(
        start: jsonText(json['start']),
        end: jsonText(json['end']),
        minutes: jsonInt(json['minutes']),
      );
}

class OpportunityItem {
  const OpportunityItem({
    required this.activityId,
    required this.name,
    required this.durationMinutes,
    required this.priceEstimate,
    required this.currency,
    required this.travelMinutesEstimate,
    required this.status,
    required this.explanation,
    required this.provenance,
    this.placeName,
    this.openingHoursToday,
    this.openingSource,
    this.lastVerifiedAt,
    this.nextStart,
  });

  final String activityId;
  final String name;
  final int durationMinutes;
  final double priceEstimate;
  final String currency;
  final int travelMinutesEstimate;
  final String status;
  final String explanation;
  final String provenance;
  final String? placeName;
  final String? openingHoursToday;
  final String? openingSource;
  final String? lastVerifiedAt;
  final String? nextStart;

  factory OpportunityItem.fromJson(Map<String, dynamic> json) =>
      OpportunityItem(
        activityId: jsonText(json['activity_id']),
        name: jsonText(json['name']),
        durationMinutes: jsonInt(json['duration_minutes']),
        priceEstimate: jsonDouble(json['price_estimate']),
        currency: jsonText(json['currency'], 'EUR'),
        travelMinutesEstimate: jsonInt(json['travel_minutes_estimate']),
        status: jsonText(json['status'], 'unknown'),
        explanation: jsonText(json['explanation']),
        provenance: jsonText(json['provenance'], 'ESTIMATED'),
        placeName: jsonString(json['place_name']),
        openingHoursToday: jsonString(json['opening_hours_today']),
        openingSource: jsonString(json['opening_source']),
        lastVerifiedAt: jsonString(json['last_verified_at']),
        nextStart: jsonString(json['next_start']),
      );
}

class OpportunitySummary {
  const OpportunitySummary({
    this.candidates = 0,
    this.openNow = 0,
    this.laterToday = 0,
    this.closedToday = 0,
    this.unknownHours = 0,
  });

  final int candidates;
  final int openNow;
  final int laterToday;
  final int closedToday;
  final int unknownHours;

  factory OpportunitySummary.fromJson(Map<String, dynamic> json) =>
      OpportunitySummary(
        candidates: jsonInt(json['candidates']),
        openNow: jsonInt(json['open_now']),
        laterToday: jsonInt(json['later_today']),
        closedToday: jsonInt(json['closed_today']),
        unknownHours: jsonInt(json['unknown_hours']),
      );
}

class OpportunityClock {
  const OpportunityClock({
    required this.date,
    required this.available,
    required this.items,
    required this.summary,
    required this.freeWindows,
    required this.plannedCount,
    required this.plannedTitles,
    required this.planUnchanged,
    required this.confirmedVersion,
    this.reason,
    this.weekday,
    this.now,
    this.explanation,
    this.disclosure,
  });

  final String date;
  final bool available;
  final List<OpportunityItem> items;
  final OpportunitySummary summary;
  final List<OpportunityWindow> freeWindows;
  final int plannedCount;
  final List<String> plannedTitles;
  final bool planUnchanged;
  final int confirmedVersion;
  final String? reason;
  final String? weekday;
  final String? now;
  final String? explanation;
  final String? disclosure;

  factory OpportunityClock.fromJson(Map<String, dynamic> json) =>
      OpportunityClock(
        date: jsonText(json['date']),
        available: jsonBool(json['available']),
        items: jsonObjects(json['items'], OpportunityItem.fromJson),
        summary: OpportunitySummary.fromJson(jsonMap(json['summary'])),
        freeWindows: jsonObjects(
          json['free_windows'],
          OpportunityWindow.fromJson,
        ),
        plannedCount: jsonInt(json['planned_count']),
        plannedTitles: jsonStringList(json['planned_titles']),
        planUnchanged: jsonBool(json['plan_unchanged'], true),
        confirmedVersion: jsonInt(json['confirmed_version']),
        reason: jsonString(json['reason']),
        weekday: jsonString(json['weekday']),
        now: jsonString(json['now']),
        explanation: jsonString(json['explanation']),
        disclosure: jsonString(json['disclosure']),
      );
}

class BranchFeasibility {
  const BranchFeasibility({
    required this.status,
    required this.note,
    this.distanceKm,
    this.travelMinutes,
  });

  final String status;
  final String note;
  final double? distanceKm;
  final int? travelMinutes;

  factory BranchFeasibility.fromJson(Map<String, dynamic> json) =>
      BranchFeasibility(
        status: jsonText(json['status'], 'unknown'),
        note: jsonText(json['note']),
        distanceKm: jsonDoubleOrNull(json['distance_km']),
        travelMinutes: jsonIntOrNull(json['travel_minutes']),
      );
}

class BranchCreation {
  const BranchCreation({required this.id, required this.feasibility});

  final String id;
  final BranchFeasibility feasibility;

  factory BranchCreation.fromJson(Map<String, dynamic> json) => BranchCreation(
    id: jsonText(json['id']),
    feasibility: BranchFeasibility.fromJson(jsonMap(json['feasibility'])),
  );
}

class EffortBudget {
  const EffortBudget({
    required this.effortPoints,
    required this.effortLevel,
    required this.walkingKmEstimate,
    required this.walkingMinutesEstimate,
    required this.transitions,
    required this.protectedRestMinutes,
    required this.heatExposure,
    required this.accessibilityNote,
    required this.disclosure,
  });

  final int effortPoints;
  final String effortLevel;
  final double walkingKmEstimate;
  final int walkingMinutesEstimate;
  final int transitions;
  final int protectedRestMinutes;
  final String heatExposure;
  final String accessibilityNote;
  final String disclosure;

  factory EffortBudget.fromJson(Map<String, dynamic> json) => EffortBudget(
    effortPoints: jsonInt(json['effort_points']),
    effortLevel: jsonText(json['effort_level'], 'light'),
    walkingKmEstimate: jsonDouble(json['walking_km_estimate']),
    walkingMinutesEstimate: jsonInt(json['walking_minutes_estimate']),
    transitions: jsonInt(json['transitions']),
    protectedRestMinutes: jsonInt(json['protected_rest_minutes']),
    heatExposure: jsonText(json['heat_exposure']),
    accessibilityNote: jsonText(json['accessibility_note']),
    disclosure: jsonText(json['disclosure']),
  );
}

class FragilityLeg {
  const FragilityLeg({
    required this.itemId,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.bufferStatus,
    required this.travelMinutes,
    required this.travelKm,
    required this.protected,
    this.bufferMinutes,
  });

  final String itemId;
  final String title;
  final String startTime;
  final String endTime;
  final String bufferStatus;
  final int travelMinutes;
  final double travelKm;
  final bool protected;
  final int? bufferMinutes;

  factory FragilityLeg.fromJson(Map<String, dynamic> json) => FragilityLeg(
    itemId: jsonText(json['item_id']),
    title: jsonText(json['title']),
    startTime: jsonText(json['start_time']),
    endTime: jsonText(json['end_time']),
    bufferStatus: jsonText(json['buffer_status'], 'comfortable'),
    travelMinutes: jsonInt(json['travel_minutes']),
    travelKm: jsonDouble(json['travel_km']),
    protected: jsonBool(json['protected']),
    bufferMinutes: jsonIntOrNull(json['buffer_minutes']),
  );
}

class FragilityTiming {
  const FragilityTiming({
    required this.itemId,
    required this.suggestion,
    required this.minutes,
  });

  final String itemId;
  final String suggestion;
  final int minutes;

  factory FragilityTiming.fromJson(Map<String, dynamic> json) =>
      FragilityTiming(
        itemId: jsonText(json['item_id']),
        suggestion: jsonText(json['suggestion']),
        minutes: jsonInt(json['minutes']),
      );
}

class FragilityDay {
  const FragilityDay({
    required this.day,
    required this.legs,
    required this.alternativeTimings,
  });

  final String day;
  final List<FragilityLeg> legs;
  final List<FragilityTiming> alternativeTimings;

  factory FragilityDay.fromJson(Map<String, dynamic> json) => FragilityDay(
    day: jsonText(json['day']),
    legs: jsonObjects(json['legs'], FragilityLeg.fromJson),
    alternativeTimings: jsonObjects(
      json['alternative_timings'],
      FragilityTiming.fromJson,
    ),
  );
}

class FragilityReport {
  const FragilityReport({
    required this.label,
    required this.days,
    required this.comfortable,
    required this.tight,
    required this.risky,
    this.resilienceScore,
    this.disclosure,
  });

  final String label;
  final List<FragilityDay> days;
  final int comfortable;
  final int tight;
  final int risky;
  final int? resilienceScore;
  final String? disclosure;

  factory FragilityReport.fromJson(Map<String, dynamic> json) {
    final summary = jsonMap(json['summary']);
    return FragilityReport(
      label: jsonText(json['label']),
      days: jsonObjects(json['days'], FragilityDay.fromJson),
      comfortable: jsonInt(summary['comfortable']),
      tight: jsonInt(summary['tight']),
      risky: jsonInt(summary['risky']),
      resilienceScore: jsonIntOrNull(json['resilience_score']),
      disclosure: jsonString(json['disclosure']),
    );
  }
}

class DominoAffected {
  const DominoAffected({
    required this.itemId,
    required this.title,
    required this.slipMinutes,
    required this.newStart,
    required this.isSource,
    required this.protected,
  });

  final String itemId;
  final String title;
  final int slipMinutes;
  final String newStart;
  final bool isSource;
  final bool protected;

  factory DominoAffected.fromJson(Map<String, dynamic> json) => DominoAffected(
    itemId: jsonText(json['item_id']),
    title: jsonText(json['title']),
    slipMinutes: jsonInt(json['slip_minutes']),
    newStart: jsonText(json['new_start']),
    isSource: jsonBool(json['is_source']),
    protected: jsonBool(json['protected']),
  );
}

class DominoUnaffected {
  const DominoUnaffected({
    required this.itemId,
    required this.title,
    required this.reason,
  });

  final String itemId;
  final String title;
  final String reason;

  factory DominoUnaffected.fromJson(Map<String, dynamic> json) =>
      DominoUnaffected(
        itemId: jsonText(json['item_id']),
        title: jsonText(json['title']),
        reason: jsonText(json['reason']),
      );
}

class DominoRepair {
  const DominoRepair({
    required this.itemId,
    required this.title,
    required this.options,
  });

  final String itemId;
  final String title;
  final List<String> options;

  factory DominoRepair.fromJson(Map<String, dynamic> json) => DominoRepair(
    itemId: jsonText(json['item_id']),
    title: jsonText(json['title']),
    options: jsonStringList(json['options']),
  );
}

class DominoMap {
  const DominoMap({
    required this.day,
    required this.disruptionItemId,
    required this.disruptionTitle,
    required this.delayMinutes,
    required this.affected,
    required this.unaffected,
    required this.minimumRepairsNeeded,
    required this.repairOptions,
    required this.disclosure,
  });

  final String day;
  final String disruptionItemId;
  final String disruptionTitle;
  final int delayMinutes;
  final List<DominoAffected> affected;
  final List<DominoUnaffected> unaffected;
  final int minimumRepairsNeeded;
  final List<DominoRepair> repairOptions;
  final String disclosure;

  factory DominoMap.fromJson(Map<String, dynamic> json) {
    final disruption = jsonMap(json['disruption']);
    return DominoMap(
      day: jsonText(json['day'] as dynamic),
      disruptionItemId: jsonText(disruption['item_id']),
      disruptionTitle: jsonText(disruption['title']),
      delayMinutes: jsonInt(disruption['delay_minutes']),
      affected: jsonObjects(json['affected'], DominoAffected.fromJson),
      unaffected: jsonObjects(json['unaffected'], DominoUnaffected.fromJson),
      minimumRepairsNeeded: jsonInt(json['minimum_repairs_needed']),
      repairOptions: jsonObjects(json['repair_options'], DominoRepair.fromJson),
      disclosure: jsonText(json['disclosure']),
    );
  }
}
