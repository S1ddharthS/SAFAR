import 'json.dart';

class InspirationCandidate {
  const InspirationCandidate({
    required this.type,
    required this.name,
    required this.confidence,
    required this.evidence,
    this.id,
    this.candidateId,
    this.kind,
    this.source,
    this.sourceSpan,
    this.provenance,
    this.verified = false,
    this.decision = 'pending',
    this.value = const {},
  });

  final String type;
  final String name;
  final double confidence;
  final String evidence;
  final String? id;
  final String? candidateId;
  final String? kind;
  final String? source;
  final String? sourceSpan;
  final String? provenance;
  final bool verified;
  final String decision;
  final Map<String, dynamic> value;

  bool get pending => decision == 'pending';

  factory InspirationCandidate.fromJson(Map<String, dynamic> json) {
    final span = jsonMap(json['source_span']);
    return InspirationCandidate(
      type: jsonText(json['type'], 'activity'),
      name: jsonText(json['name']),
      confidence: jsonDouble(json['confidence']),
      evidence: jsonText(json['evidence']),
      id: jsonString(json['id']),
      candidateId: jsonString(json['candidate_id']),
      kind: jsonString(json['kind']),
      source: jsonString(json['source']),
      sourceSpan: jsonString(span['text']),
      provenance: jsonString(json['provenance']),
      verified: jsonBool(json['verified']),
      decision: jsonText(json['decision'], 'pending'),
      value: jsonMap(json['value']),
    );
  }
}

class InspirationProviderState {
  const InspirationProviderState({
    required this.provider,
    required this.ok,
    required this.provenance,
    this.error,
    this.message,
    this.attribution,
  });

  final String provider;
  final bool ok;
  final String provenance;
  final String? error;
  final String? message;
  final String? attribution;

  factory InspirationProviderState.fromJson(Map<String, dynamic> json) =>
      InspirationProviderState(
        provider: jsonText(json['provider']),
        ok: jsonBool(json['ok']),
        provenance: jsonText(json['provenance']),
        error: jsonString(json['error']),
        message: jsonString(json['message']),
        attribution: jsonString(json['attribution']),
      );
}

class InspirationLinkMeta {
  const InspirationLinkMeta({
    this.title,
    this.description,
    this.siteName,
    this.sourceUrl,
  });

  final String? title;
  final String? description;
  final String? siteName;
  final String? sourceUrl;

  factory InspirationLinkMeta.fromJson(Map<String, dynamic> json) =>
      InspirationLinkMeta(
        title: jsonString(json['title']),
        description: jsonString(json['description']),
        siteName: jsonString(json['site_name']),
        sourceUrl: jsonString(json['source_url']),
      );
}

class InspirationOcr {
  const InspirationOcr({
    required this.available,
    required this.characters,
    required this.preview,
  });

  final bool available;
  final int characters;
  final String preview;

  factory InspirationOcr.fromJson(Map<String, dynamic> json) => InspirationOcr(
    available: jsonBool(json['available']),
    characters: jsonInt(json['characters']),
    preview: jsonText(json['preview']),
  );
}

class InspirationExtraction {
  const InspirationExtraction({
    this.matches = const [],
    this.notes = const [],
    this.limitations = const [],
    this.pending = 0,
    this.accepted = 0,
    this.rejected = 0,
    this.sourceHosts = const [],
    this.hashtags = const [],
    this.providers = const [],
    this.link,
    this.ocr,
  });

  final List<InspirationCandidate> matches;
  final List<String> notes;
  final List<String> limitations;
  final int pending;
  final int accepted;
  final int rejected;
  final List<String> sourceHosts;
  final List<String> hashtags;
  final List<InspirationProviderState> providers;
  final InspirationLinkMeta? link;
  final InspirationOcr? ocr;

  factory InspirationExtraction.fromJson(Map<String, dynamic> json) {
    final review = jsonMap(json['review']);
    final metadata = jsonMap(json['metadata']);
    final link = jsonMap(metadata['link']);
    final ocr = jsonMap(metadata['ocr']);
    return InspirationExtraction(
      matches: jsonObjects(json['matches'], InspirationCandidate.fromJson),
      notes: jsonStringList(json['notes']),
      limitations: jsonStringList(json['limitations']),
      pending: jsonInt(review['pending']),
      accepted: jsonInt(review['accepted']),
      rejected: jsonInt(review['rejected']),
      sourceHosts: jsonStringList(metadata['source_hosts']),
      hashtags: jsonStringList(metadata['hashtags']),
      providers: jsonObjects(
        metadata['providers'],
        InspirationProviderState.fromJson,
      ),
      link: link.isEmpty ? null : InspirationLinkMeta.fromJson(link),
      ocr: ocr.isEmpty ? null : InspirationOcr.fromJson(ocr),
    );
  }
}

class InspirationItem {
  const InspirationItem({
    required this.id,
    required this.sourceType,
    required this.content,
    required this.status,
    required this.extracted,
    required this.createdAt,
  });

  final String id;
  final String sourceType;
  final String content;
  final String status;
  final InspirationExtraction extracted;
  final String createdAt;

  factory InspirationItem.fromJson(Map<String, dynamic> json) =>
      InspirationItem(
        id: jsonText(json['id']),
        sourceType: jsonText(json['source_type'], 'text'),
        content: jsonText(json['content']),
        status: jsonText(json['status'], 'pending'),
        extracted: InspirationExtraction.fromJson(
          jsonMap(json['extracted']),
        ),
        createdAt: jsonText(json['created_at']),
      );
}
