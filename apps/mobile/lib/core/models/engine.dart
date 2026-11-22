import 'discovery.dart';
import 'json.dart';

class EngineModeInfo {
  const EngineModeInfo({this.label = '', this.intent = ''});

  final String label;
  final String intent;

  factory EngineModeInfo.fromJson(Map<String, dynamic> json) => EngineModeInfo(
    label: jsonText(json['label']),
    intent: jsonText(json['intent']),
  );
}

class FairnessEvaluation {
  const FairnessEvaluation({
    this.leastServedMeanFit = 0,
    this.memberMeanSpread = 0,
    this.jainIndex = 0,
    this.note,
  });

  final double leastServedMeanFit;
  final double memberMeanSpread;
  final double jainIndex;
  final String? note;

  factory FairnessEvaluation.fromJson(Map<String, dynamic> json) =>
      FairnessEvaluation(
        leastServedMeanFit: jsonDouble(json['least_served_member_mean_fit']),
        memberMeanSpread: jsonDouble(json['member_mean_spread']),
        jainIndex: jsonDouble(json['jain_index']),
        note: jsonString(json['note']),
      );
}

class SatisfactionEvaluation {
  const SatisfactionEvaluation({
    this.meanAverageFit = 0,
    this.meanMinimumFit = 0,
    this.meanNovelty = 0,
  });

  final double meanAverageFit;
  final double meanMinimumFit;
  final double meanNovelty;

  factory SatisfactionEvaluation.fromJson(Map<String, dynamic> json) =>
      SatisfactionEvaluation(
        meanAverageFit: jsonDouble(json['mean_average_fit']),
        meanMinimumFit: jsonDouble(json['mean_minimum_fit']),
        meanNovelty: jsonDouble(json['mean_novelty']),
      );
}

class ConstraintsEvaluation {
  const ConstraintsEvaluation({
    this.violations = 0,
    this.eligible = 0,
    this.excluded = 0,
    this.note,
  });

  final int violations;
  final int eligible;
  final int excluded;
  final String? note;

  factory ConstraintsEvaluation.fromJson(Map<String, dynamic> json) =>
      ConstraintsEvaluation(
        violations: jsonInt(json['violations']),
        eligible: jsonInt(json['eligible']),
        excluded: jsonInt(json['excluded']),
        note: jsonString(json['note']),
      );
}

class DiversityEvaluation {
  const DiversityEvaluation({
    this.uniquePrimaryTags = 0,
    this.uniqueTags = 0,
    this.meanPairwiseSimilarity = 0,
    this.note,
  });

  final int uniquePrimaryTags;
  final int uniqueTags;
  final double meanPairwiseSimilarity;
  final String? note;

  factory DiversityEvaluation.fromJson(Map<String, dynamic> json) =>
      DiversityEvaluation(
        uniquePrimaryTags: jsonInt(json['unique_primary_tags']),
        uniqueTags: jsonInt(json['unique_tags']),
        meanPairwiseSimilarity: jsonDouble(json['mean_pairwise_similarity']),
        note: jsonString(json['note']),
      );
}

class EngineEvaluation {
  const EngineEvaluation({
    required this.fairness,
    required this.satisfaction,
    required this.constraints,
    required this.diversity,
  });

  final FairnessEvaluation fairness;
  final SatisfactionEvaluation satisfaction;
  final ConstraintsEvaluation constraints;
  final DiversityEvaluation diversity;

  factory EngineEvaluation.fromJson(Map<String, dynamic> json) =>
      EngineEvaluation(
        fairness: FairnessEvaluation.fromJson(jsonMap(json['fairness'])),
        satisfaction: SatisfactionEvaluation.fromJson(
          jsonMap(json['satisfaction']),
        ),
        constraints: ConstraintsEvaluation.fromJson(
          jsonMap(json['constraints']),
        ),
        diversity: DiversityEvaluation.fromJson(jsonMap(json['diversity'])),
      );
}

class FeedbackLearning {
  const FeedbackLearning({
    this.appliedActivities = 0,
    this.consentedRaters = 0,
    this.enabled = false,
    this.maxAdjustment = 0,
    this.note,
  });

  final int appliedActivities;
  final int consentedRaters;
  final bool enabled;
  final double maxAdjustment;
  final String? note;

  factory FeedbackLearning.fromJson(Map<String, dynamic> json) =>
      FeedbackLearning(
        appliedActivities: jsonInt(json['applied_activities']),
        consentedRaters: jsonInt(json['consented_raters']),
        enabled: jsonBool(json['enabled']),
        maxAdjustment: jsonDouble(json['max_adjustment']),
        note: jsonString(json['note']),
      );
}

class ProtectedItem {
  const ProtectedItem({
    required this.itemId,
    required this.title,
    required this.start,
    required this.end,
    required this.protected,
  });

  final String itemId;
  final String title;
  final String start;
  final String end;
  final bool protected;

  factory ProtectedItem.fromJson(Map<String, dynamic> json) => ProtectedItem(
    itemId: jsonText(json['item_id']),
    title: jsonText(json['title']),
    start: jsonText(json['start']),
    end: jsonText(json['end']),
    protected: jsonBool(json['protected']),
  );
}

class FreeWindow {
  const FreeWindow({
    required this.start,
    required this.end,
    required this.minutes,
  });

  final String start;
  final String end;
  final int minutes;

  factory FreeWindow.fromJson(Map<String, dynamic> json) => FreeWindow(
    start: jsonText(json['start']),
    end: jsonText(json['end']),
    minutes: jsonInt(json['minutes']),
  );
}

class ProtectedTime {
  const ProtectedTime({
    this.protectedItems = const [],
    this.freeWindows = const [],
    this.maxFreeMinutes = 0,
    this.note,
  });

  final List<ProtectedItem> protectedItems;
  final List<FreeWindow> freeWindows;
  final int maxFreeMinutes;
  final String? note;

  factory ProtectedTime.fromJson(Map<String, dynamic> json) => ProtectedTime(
    protectedItems: jsonObjects(
      json['protected_items'],
      ProtectedItem.fromJson,
    ),
    freeWindows: jsonObjects(json['free_windows'], FreeWindow.fromJson),
    maxFreeMinutes: jsonInt(json['max_free_minutes']),
    note: jsonString(json['note']),
  );
}

class EngineMeta {
  const EngineMeta({
    this.candidateCount = 0,
    this.eligibleCount = 0,
    this.excludedCount = 0,
    this.membersCount = 0,
    this.pulseCoverage,
    this.disclosure,
    this.clarifyingQuestion,
    this.rankingFormula,
    this.targetMember,
    this.alternativeCount = 0,
    this.exclusionReasons = const {},
    this.evaluation,
    this.feedbackLearning,
    this.protectedTime,
  });

  final int candidateCount;
  final int eligibleCount;
  final int excludedCount;
  final int membersCount;
  final String? pulseCoverage;
  final String? disclosure;
  final String? clarifyingQuestion;
  final String? rankingFormula;
  final String? targetMember;
  final int alternativeCount;
  final Map<String, dynamic> exclusionReasons;
  final EngineEvaluation? evaluation;
  final FeedbackLearning? feedbackLearning;
  final ProtectedTime? protectedTime;

  factory EngineMeta.fromJson(Map<String, dynamic> json) {
    final evaluation = jsonMap(json['evaluation']);
    final feedback = jsonMap(json['feedback_learning']);
    final protectedTime = jsonMap(json['protected_time']);
    return EngineMeta(
      candidateCount: jsonInt(json['candidate_count']),
      eligibleCount: jsonInt(json['eligible_count']),
      excludedCount: jsonInt(json['excluded_count']),
      membersCount: jsonInt(json['members_count']),
      pulseCoverage: jsonString(json['pulse_coverage']),
      disclosure: jsonString(json['disclosure']),
      clarifyingQuestion: jsonString(json['clarifying_question']),
      rankingFormula: jsonString(json['ranking_formula']),
      targetMember: jsonString(json['target_member']),
      alternativeCount: jsonInt(json['alternative_count']),
      exclusionReasons: jsonMap(json['exclusion_reasons']),
      evaluation: evaluation.isEmpty
          ? null
          : EngineEvaluation.fromJson(evaluation),
      feedbackLearning: feedback.isEmpty
          ? null
          : FeedbackLearning.fromJson(feedback),
      protectedTime: protectedTime.isEmpty
          ? null
          : ProtectedTime.fromJson(protectedTime),
    );
  }
}

class SelectionNote {
  const SelectionNote({
    this.diversityPenalty = 0,
    this.feedbackAdjustment = 0,
    this.note = '',
  });

  final double diversityPenalty;
  final double feedbackAdjustment;
  final String note;

  factory SelectionNote.fromJson(Map<String, dynamic> json) => SelectionNote(
    diversityPenalty: jsonDouble(json['diversity_penalty']),
    feedbackAdjustment: jsonDouble(json['feedback_adjustment']),
    note: jsonText(json['note']),
  );
}

class AlternativeActivity {
  const AlternativeActivity({
    required this.activityId,
    required this.name,
    required this.scoreDelta,
  });

  final String activityId;
  final String name;
  final double scoreDelta;

  factory AlternativeActivity.fromJson(Map<String, dynamic> json) =>
      AlternativeActivity(
        activityId: jsonText(json['activity_id']),
        name: jsonText(json['name']),
        scoreDelta: jsonDouble(json['score_delta']),
      );
}

class ConstraintCheck {
  const ConstraintCheck({
    required this.constraint,
    required this.status,
    required this.detail,
  });

  final String constraint;
  final String status;
  final String detail;

  factory ConstraintCheck.fromJson(Map<String, dynamic> json) =>
      ConstraintCheck(
        constraint: jsonText(json['constraint']),
        status: jsonText(json['status']),
        detail: jsonText(json['detail']),
      );
}

class DataFreshness {
  const DataFreshness({required this.label, this.ageDays, this.lastVerifiedAt});

  final String label;
  final int? ageDays;
  final String? lastVerifiedAt;

  factory DataFreshness.fromJson(Map<String, dynamic> json) => DataFreshness(
    label: jsonText(json['label'], 'catalog'),
    ageDays: jsonIntOrNull(json['age_days']),
    lastVerifiedAt: jsonString(json['last_verified_at']),
  );
}

class RecommendationExplanation {
  const RecommendationExplanation({
    required this.summary,
    this.whySelected = const [],
    this.suits = const [],
    this.mayNotPrefer = const [],
    this.constraintsChecked = const [],
    this.estimatedCost = 0,
    this.currency = 'EUR',
    this.distanceKm = 0,
    this.travelMinutes = 0,
    this.durationMinutes = 0,
    this.dataFreshness,
    this.uncertainties = const [],
    this.metrics = const {},
    this.memberFitsAnonymous = const [],
    this.targetMember,
    this.selection,
    this.alternatives = const [],
  });

  final String summary;
  final List<String> whySelected;
  final List<String> suits;
  final List<String> mayNotPrefer;
  final List<ConstraintCheck> constraintsChecked;
  final double estimatedCost;
  final String currency;
  final double distanceKm;
  final int travelMinutes;
  final int durationMinutes;
  final DataFreshness? dataFreshness;
  final List<String> uncertainties;
  final Map<String, double> metrics;
  final List<double> memberFitsAnonymous;
  final String? targetMember;
  final SelectionNote? selection;
  final List<AlternativeActivity> alternatives;

  factory RecommendationExplanation.fromJson(Map<String, dynamic> json) {
    final freshness = jsonMap(json['data_freshness']);
    final selection = jsonMap(json['selection']);
    final metrics = <String, double>{};
    jsonMap(json['metrics']).forEach((key, value) {
      metrics[key] = jsonDouble(value);
    });
    return RecommendationExplanation(
      summary: jsonText(json['summary']),
      whySelected: jsonStringList(json['why_selected']),
      suits: jsonStringList(json['suits']),
      mayNotPrefer: jsonStringList(json['may_not_prefer']),
      constraintsChecked: jsonObjects(
        json['constraints_checked'],
        ConstraintCheck.fromJson,
      ),
      estimatedCost: jsonDouble(json['estimated_cost']),
      currency: jsonText(json['currency'], 'EUR'),
      distanceKm: jsonDouble(json['distance_km']),
      travelMinutes: jsonInt(json['travel_minutes']),
      durationMinutes: jsonInt(json['duration_minutes']),
      dataFreshness: freshness.isEmpty
          ? null
          : DataFreshness.fromJson(freshness),
      uncertainties: jsonStringList(json['uncertainties']),
      metrics: metrics,
      memberFitsAnonymous: jsonList(
        json['member_fits_anonymous'],
      ).map((value) => jsonDouble(value)).toList(),
      targetMember: jsonString(json['target_member']),
      selection: selection.isEmpty
          ? null
          : SelectionNote.fromJson(selection),
      alternatives: jsonObjects(
        json['alternatives'],
        AlternativeActivity.fromJson,
      ),
    );
  }
}

class RecommendationRespect {
  const RecommendationRespect({
    required this.fragile,
    required this.confidence,
    required this.status,
    this.guidance,
  });

  final bool fragile;
  final String confidence;
  final String status;
  final String? guidance;

  factory RecommendationRespect.fromJson(Map<String, dynamic> json) =>
      RecommendationRespect(
        fragile: jsonBool(json['fragile']),
        confidence: jsonText(json['confidence']),
        status: jsonText(json['status']),
        guidance: jsonString(json['guidance']),
      );
}

class RecommendationItem {
  const RecommendationItem({
    required this.id,
    required this.activityId,
    required this.rank,
    required this.score,
    required this.averageFit,
    required this.minimumFit,
    required this.fairnessSpread,
    required this.novelty,
    required this.penalties,
    required this.explanation,
    this.status = 'suggested',
    this.activity,
    this.myFeedback,
    this.respect,
  });

  final String id;
  final String activityId;
  final int rank;
  final double score;
  final double averageFit;
  final double minimumFit;
  final double fairnessSpread;
  final double novelty;
  final Map<String, double> penalties;
  final RecommendationExplanation explanation;
  final String status;
  final Activity? activity;
  final String? myFeedback;
  final RecommendationRespect? respect;

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    final penalties = <String, double>{};
    jsonMap(json['penalties']).forEach((key, value) {
      penalties[key] = jsonDouble(value);
    });
    final activityJson = jsonMap(json['activity']);
    final respectJson = jsonMap(json['respect']);
    return RecommendationItem(
      id: jsonText(json['id']),
      activityId: jsonText(json['activity_id']),
      rank: jsonInt(json['rank']),
      score: jsonDouble(json['score']),
      averageFit: jsonDouble(json['average_fit']),
      minimumFit: jsonDouble(json['minimum_fit']),
      fairnessSpread: jsonDouble(json['fairness_spread']),
      novelty: jsonDouble(json['novelty']),
      penalties: penalties,
      explanation: RecommendationExplanation.fromJson(
        jsonMap(json['explanation']),
      ),
      status: jsonText(json['status'], 'suggested'),
      activity: activityJson.isEmpty ? null : Activity.fromJson(activityJson),
      myFeedback: jsonString(json['my_feedback']),
      respect: respectJson.isEmpty
          ? null
          : RecommendationRespect.fromJson(respectJson),
    );
  }
}

class EngineBatch {
  const EngineBatch({
    required this.mode,
    required this.modeMeta,
    required this.items,
    required this.meta,
    this.id,
    this.forDate,
    this.modelVersion,
    this.createdAt,
    this.message,
  });

  final String? id;
  final String mode;
  final EngineModeInfo modeMeta;
  final List<RecommendationItem> items;
  final EngineMeta meta;
  final String? forDate;
  final String? modelVersion;
  final String? createdAt;
  final String? message;

  factory EngineBatch.fromJson(Map<String, dynamic> json) => EngineBatch(
    id: jsonString(json['id']),
    mode: jsonText(json['mode'], 'everyone_wins'),
    modeMeta: EngineModeInfo.fromJson(jsonMap(json['mode_meta'])),
    items: jsonObjects(json['items'], RecommendationItem.fromJson),
    meta: EngineMeta.fromJson(jsonMap(json['meta'])),
    forDate: jsonString(json['for_date']),
    modelVersion: jsonString(json['model_version']),
    createdAt: jsonString(json['created_at']),
    message: jsonString(json['message']),
  );
}

class RescueDisruption {
  const RescueDisruption({
    required this.kind,
    required this.label,
    this.note,
    this.extraMinutes,
  });

  final String kind;
  final String label;
  final String? note;
  final int? extraMinutes;

  factory RescueDisruption.fromJson(Map<String, dynamic> json) =>
      RescueDisruption(
        kind: jsonText(json['kind']),
        label: jsonText(json['label']),
        note: jsonString(json['note']),
        extraMinutes: jsonIntOrNull(json['extra_minutes']),
      );
}

class RescueAffectedItem {
  const RescueAffectedItem({
    required this.itemId,
    required this.title,
    required this.startTime,
    required this.reason,
  });

  final String itemId;
  final String title;
  final String startTime;
  final String reason;

  factory RescueAffectedItem.fromJson(Map<String, dynamic> json) =>
      RescueAffectedItem(
        itemId: jsonText(json['item_id']),
        title: jsonText(json['title']),
        startTime: jsonText(json['start_time']),
        reason: jsonText(json['reason']),
      );
}

class RescueOption {
  const RescueOption({
    this.activityId,
    required this.name,
    this.price,
    this.duration,
    this.indoor,
    this.effort,
    this.source = 'catalog',
    this.score,
    this.note,
    this.ready = false,
  });

  final String? activityId;
  final String name;
  final double? price;
  final int? duration;
  final bool? indoor;
  final int? effort;
  final String source;
  final double? score;
  final String? note;
  final bool ready;

  factory RescueOption.fromJson(Map<String, dynamic> json) => RescueOption(
    activityId: jsonString(json['activity_id']),
    name: jsonText(json['name']),
    price: jsonDoubleOrNull(json['price']),
    duration: jsonIntOrNull(json['duration']),
    indoor: json['indoor'] == null ? null : jsonBool(json['indoor']),
    effort: jsonIntOrNull(json['effort']),
    source: jsonText(json['source'], 'catalog'),
    score: jsonDoubleOrNull(json['score']),
    note: jsonString(json['note']),
    ready: jsonBool(json['ready']),
  );
}

class RescueProposal {
  const RescueProposal({
    required this.itemId,
    required this.day,
    required this.title,
    required this.startTime,
    required this.reason,
    required this.options,
    this.recommended,
    this.recommendedActivityId,
    this.travelMinutes = 0,
  });

  final String itemId;
  final String day;
  final String title;
  final String startTime;
  final String reason;
  final List<RescueOption> options;
  final String? recommended;
  final String? recommendedActivityId;
  final int travelMinutes;

  factory RescueProposal.fromJson(Map<String, dynamic> json) => RescueProposal(
    itemId: jsonText(json['item_id']),
    day: jsonText(json['day']),
    title: jsonText(json['title']),
    startTime: jsonText(json['start_time']),
    reason: jsonText(json['reason']),
    options: jsonObjects(json['options'], RescueOption.fromJson),
    recommended: jsonString(json['recommended']),
    recommendedActivityId: jsonString(json['recommended_activity_id']),
    travelMinutes: jsonInt(json['travel_minutes']),
  );
}

class RescueConsequences {
  const RescueConsequences({
    this.costDelta = 0,
    this.durationDeltaMinutes = 0,
    this.timeSavedOrLost = '',
    this.pactConflictCount = 0,
    this.protectedRespected = true,
  });

  final double costDelta;
  final int durationDeltaMinutes;
  final String timeSavedOrLost;
  final int pactConflictCount;
  final bool protectedRespected;

  factory RescueConsequences.fromJson(Map<String, dynamic> json) =>
      RescueConsequences(
        costDelta: jsonDouble(json['cost_delta']),
        durationDeltaMinutes: jsonInt(json['duration_delta_minutes']),
        timeSavedOrLost: jsonText(json['time_saved_or_lost']),
        pactConflictCount: jsonList(json['pact_conflicts']).length,
        protectedRespected: jsonBool(json['protected_respected'], true),
      );
}

class RescueAnalysis {
  const RescueAnalysis({
    required this.disruption,
    required this.affected,
    required this.proposals,
    this.protected = const [],
    this.message,
    this.consequences,
    this.requiresApproval = true,
    this.disclosure,
  });

  final RescueDisruption disruption;
  final List<RescueAffectedItem> affected;
  final List<RescueProposal> proposals;
  final List<RescueAffectedItem> protected;
  final String? message;
  final RescueConsequences? consequences;
  final bool requiresApproval;
  final String? disclosure;

  factory RescueAnalysis.fromJson(Map<String, dynamic> json) {
    final consequences = jsonMap(json['consequences']);
    return RescueAnalysis(
      disruption: RescueDisruption.fromJson(jsonMap(json['disruption'])),
      affected: jsonObjects(json['affected'], RescueAffectedItem.fromJson),
      proposals: jsonObjects(json['proposals'], RescueProposal.fromJson),
      protected: jsonObjects(json['protected'], RescueAffectedItem.fromJson),
      message: jsonString(json['message']),
      consequences: consequences.isEmpty
          ? null
          : RescueConsequences.fromJson(consequences),
      requiresApproval: jsonBool(json['requires_approval'], true),
      disclosure: jsonString(json['disclosure']),
    );
  }
}
