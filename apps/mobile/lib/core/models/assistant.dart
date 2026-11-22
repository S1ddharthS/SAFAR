import 'json.dart';

class Citation {
  const Citation({
    required this.label,
    required this.type,
    this.id,
    this.provenance,
  });

  final String label;
  final String type;
  final String? id;
  final String? provenance;

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
    label: jsonText(json['label']),
    type: jsonText(json['type'], 'record'),
    id: jsonString(json['id']),
    provenance: jsonString(json['provenance']),
  );
}

class SuggestedAction {
  const SuggestedAction({required this.label, this.href, this.action});

  final String label;
  final String? href;
  final String? action;

  factory SuggestedAction.fromJson(Map<String, dynamic> json) =>
      SuggestedAction(
        label: jsonText(json['label']),
        href: jsonString(json['href']),
        action: jsonString(json['action']),
      );
}

class AnswerLanguage {
  const AnswerLanguage({
    required this.code,
    required this.name,
    required this.source,
    this.detected,
    this.mixed = const [],
    this.unsupported,
  });

  final String code;
  final String name;
  final String source;
  final String? detected;
  final List<String> mixed;
  final String? unsupported;

  factory AnswerLanguage.fromJson(Map<String, dynamic> json) => AnswerLanguage(
    code: jsonText(json['code'], 'en'),
    name: jsonText(json['name'], 'English'),
    source: jsonText(json['source'], 'default'),
    detected: jsonString(json['detected']),
    mixed: jsonStringList(json['mixed']),
    unsupported: jsonString(json['unsupported']),
  );
}

class AnswerGroupPreferences {
  const AnswerGroupPreferences({
    required this.consentedMembers,
    required this.totalMembers,
  });

  final int consentedMembers;
  final int totalMembers;

  factory AnswerGroupPreferences.fromJson(Map<String, dynamic> json) =>
      AnswerGroupPreferences(
        consentedMembers: jsonInt(json['consented_members']),
        totalMembers: jsonInt(json['total_members']),
      );
}

class AnswerContext {
  const AnswerContext({
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.groupSize,
    this.missing = const [],
    this.groupPreferences,
  });

  final String? destination;
  final String startDate;
  final String endDate;
  final int groupSize;
  final List<String> missing;
  final AnswerGroupPreferences? groupPreferences;

  factory AnswerContext.fromJson(Map<String, dynamic> json) {
    final trip = jsonMap(json['trip']);
    final group = jsonMap(json['group_preferences']);
    return AnswerContext(
      destination: jsonString(trip['destination']),
      startDate: jsonText(trip['start_date']),
      endDate: jsonText(trip['end_date']),
      groupSize: jsonInt(trip['group_size']),
      missing: jsonStringList(json['missing']),
      groupPreferences: group.isEmpty
          ? null
          : AnswerGroupPreferences.fromJson(group),
    );
  }
}

class AssistantAnswer {
  const AssistantAnswer({
    required this.intent,
    required this.answer,
    required this.grounding,
    this.citations = const [],
    this.limitations = const [],
    this.suggestedActions = const [],
    this.language,
    this.context,
    this.mutation = 'none',
    this.requiresApproval = false,
    this.attribution,
    this.generatedBy,
  });

  final String intent;
  final String answer;
  final String grounding;
  final List<Citation> citations;
  final List<String> limitations;
  final List<SuggestedAction> suggestedActions;
  final AnswerLanguage? language;
  final AnswerContext? context;
  final String mutation;
  final bool requiresApproval;
  final String? attribution;
  final String? generatedBy;

  factory AssistantAnswer.fromJson(Map<String, dynamic> json) {
    final language = jsonMap(json['language']);
    final context = jsonMap(json['context']);
    return AssistantAnswer(
      intent: jsonText(json['intent'], 'general'),
      answer: jsonText(json['answer']),
      grounding: jsonText(json['grounding'], 'product'),
      citations: jsonObjects(json['citations'], Citation.fromJson),
      limitations: jsonStringList(json['limitations']),
      suggestedActions: jsonObjects(
        json['suggested_actions'],
        SuggestedAction.fromJson,
      ),
      language: language.isEmpty
          ? null
          : AnswerLanguage.fromJson(language),
      context: context.isEmpty ? null : AnswerContext.fromJson(context),
      mutation: jsonText(json['mutation'], 'none'),
      requiresApproval: jsonBool(json['requires_approval']),
      attribution: jsonString(json['attribution']),
      generatedBy: jsonString(json['generated_by']),
    );
  }
}
