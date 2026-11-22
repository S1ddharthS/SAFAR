import 'json.dart';

class Destination {
  const Destination({
    required this.id,
    required this.slug,
    required this.name,
    required this.country,
    required this.description,
    required this.lat,
    required this.lon,
    this.region,
    this.heroImage,
    this.tags = const [],
    this.bestMonths = const [],
    this.sourceType = 'catalog',
    this.sourceName = '',
    this.activityCount = 0,
    this.disclosure,
  });

  final String id;
  final String slug;
  final String name;
  final String country;
  final String description;
  final double lat;
  final double lon;
  final String? region;
  final String? heroImage;
  final List<String> tags;
  final List<int> bestMonths;
  final String sourceType;
  final String sourceName;
  final int activityCount;
  final String? disclosure;

  String get location => [region, country].whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' · ');

  factory Destination.fromJson(Map<String, dynamic> json) => Destination(
    id: jsonText(json['id']),
    slug: jsonText(json['slug']),
    name: jsonText(json['name']),
    country: jsonText(json['country']),
    description: jsonText(json['description']),
    lat: jsonDouble(json['lat']),
    lon: jsonDouble(json['lon']),
    region: jsonString(json['region']),
    heroImage: jsonString(json['hero_image']),
    tags: jsonStringList(json['tags']),
    bestMonths: jsonList(json['best_months']).map((m) => jsonInt(m)).toList(),
    sourceType: jsonText(json['source_type'], 'catalog'),
    sourceName: jsonText(json['source_name']),
    activityCount: jsonInt(json['activity_count']),
    disclosure: jsonString(json['disclosure']),
  );
}

class Place {
  const Place({
    required this.id,
    required this.destinationId,
    required this.name,
    required this.category,
    required this.description,
    required this.lat,
    required this.lon,
    this.address,
    this.fragile = false,
    this.respectNote,
    this.sourceType,
    this.sourceName,
    this.lastVerifiedAt,
  });

  final String id;
  final String destinationId;
  final String name;
  final String category;
  final String description;
  final double lat;
  final double lon;
  final String? address;
  final bool fragile;
  final String? respectNote;
  final String? sourceType;
  final String? sourceName;
  final String? lastVerifiedAt;

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    id: jsonText(json['id']),
    destinationId: jsonText(json['destination_id']),
    name: jsonText(json['name']),
    category: jsonText(json['category']),
    description: jsonText(json['description']),
    lat: jsonDouble(json['lat']),
    lon: jsonDouble(json['lon']),
    address: jsonString(json['address']),
    fragile: jsonBool(json['fragile']),
    respectNote: jsonString(json['respect_note']),
    sourceType: jsonString(json['source_type']),
    sourceName: jsonString(json['source_name']),
    lastVerifiedAt: jsonString(json['last_verified_at']),
  );
}

class Activity {
  const Activity({
    required this.id,
    required this.placeId,
    required this.destinationId,
    required this.name,
    required this.description,
    this.tags = const [],
    this.priceEstimate = 0,
    this.currency = 'EUR',
    this.durationMinutes = 0,
    this.effort = 1,
    this.indoor = false,
    this.wheelchairAccessible,
    this.iconic = false,
    this.popularity = 0,
    this.fragile = false,
    this.openingHours = const {},
    this.imageUrl,
    this.sourceType,
    this.lastVerifiedAt,
    this.place,
    this.destination,
  });

  final String id;
  final String placeId;
  final String destinationId;
  final String name;
  final String description;
  final List<String> tags;
  final double priceEstimate;
  final String currency;
  final int durationMinutes;
  final int effort;
  final bool indoor;
  final bool? wheelchairAccessible;
  final bool iconic;
  final double popularity;
  final bool fragile;
  final Map<String, String> openingHours;
  final String? imageUrl;
  final String? sourceType;
  final String? lastVerifiedAt;
  final Place? place;
  final Destination? destination;

  factory Activity.fromJson(Map<String, dynamic> json) {
    final hours = <String, String>{};
    jsonMap(json['opening_hours']).forEach((key, value) {
      final text = jsonString(value);
      if (text != null) hours[key] = text;
    });
    final placeJson = jsonMap(json['place']);
    final destinationJson = jsonMap(json['destination']);
    return Activity(
      id: jsonText(json['id']),
      placeId: jsonText(json['place_id']),
      destinationId: jsonText(json['destination_id']),
      name: jsonText(json['name']),
      description: jsonText(json['description']),
      tags: jsonStringList(json['tags']),
      priceEstimate: jsonDouble(json['price_estimate']),
      currency: jsonText(json['currency'], 'EUR'),
      durationMinutes: jsonInt(json['duration_minutes']),
      effort: jsonInt(json['effort'], 1),
      indoor: jsonBool(json['indoor']),
      wheelchairAccessible: json['wheelchair_accessible'] == null
          ? null
          : jsonBool(json['wheelchair_accessible']),
      iconic: jsonBool(json['iconic']),
      popularity: jsonDouble(json['popularity']),
      fragile: jsonBool(json['fragile']),
      openingHours: hours,
      imageUrl: jsonString(json['image_url']),
      sourceType: jsonString(json['source_type']),
      lastVerifiedAt: jsonString(json['last_verified_at']),
      place: placeJson.isEmpty ? null : Place.fromJson(placeJson),
      destination: destinationJson.isEmpty
          ? null
          : Destination.fromJson(destinationJson),
    );
  }
}

class CatalogFreshness {
  const CatalogFreshness({required this.label, this.lastVerifiedAt});

  final String label;
  final String? lastVerifiedAt;

  factory CatalogFreshness.fromJson(Map<String, dynamic> json) =>
      CatalogFreshness(
        label: jsonText(json['label'], 'catalog data'),
        lastVerifiedAt: jsonString(json['last_verified_at']),
      );
}

class SearchItem {
  const SearchItem({
    required this.activity,
    this.personalFit = 0,
    this.similarTo,
    this.similarity,
    this.respectNote,
    this.provenance = 'ESTIMATED',
    this.catalogFreshness,
  });

  final Activity activity;
  final int personalFit;
  final String? similarTo;
  final double? similarity;
  final String? respectNote;
  final String provenance;
  final CatalogFreshness? catalogFreshness;

  factory SearchItem.fromJson(Map<String, dynamic> json) {
    final freshness = jsonMap(json['catalog_freshness']);
    return SearchItem(
      activity: Activity.fromJson(jsonMap(json['activity'])),
      personalFit: jsonInt(json['personal_fit']),
      similarTo: jsonString(json['similar_to']),
      similarity: jsonDoubleOrNull(json['similarity']),
      respectNote: jsonString(json['respect_note']),
      provenance: jsonText(json['provenance'], 'ESTIMATED'),
      catalogFreshness: freshness.isEmpty
          ? null
          : CatalogFreshness.fromJson(freshness),
    );
  }
}

class SearchResult {
  const SearchResult({
    required this.lens,
    required this.items,
    required this.personalised,
    required this.disclosure,
  });

  final String lens;
  final List<SearchItem> items;
  final bool personalised;
  final String disclosure;

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    lens: jsonText(json['lens'], 'best_match'),
    items: jsonObjects(json['items'], SearchItem.fromJson),
    personalised: jsonBool(json['personalised']),
    disclosure: jsonText(json['disclosure']),
  );
}

class DestinationDetail {
  const DestinationDetail({
    required this.destination,
    this.sampleActivities = const [],
  });

  final Destination destination;
  final List<SearchItem> sampleActivities;

  factory DestinationDetail.fromJson(Map<String, dynamic> json) =>
      DestinationDetail(
        destination: Destination.fromJson(
          json.containsKey('destination') ? jsonMap(json['destination']) : json,
        ),
        sampleActivities: jsonObjects(
          json['sample_activities'],
          SearchItem.fromJson,
        ),
      );
}

class PlaceReportAggregate {
  const PlaceReportAggregate({
    required this.activityId,
    required this.windowDays,
    required this.hasData,
    required this.disclosure,
    this.categories = const [],
  });

  final String activityId;
  final int windowDays;
  final bool hasData;
  final String disclosure;
  final List<PlaceReportCategory> categories;

  factory PlaceReportAggregate.fromJson(Map<String, dynamic> json) =>
      PlaceReportAggregate(
        activityId: jsonText(json['activity_id']),
        windowDays: jsonInt(json['window_days'], 90),
        hasData: jsonBool(json['has_data']),
        disclosure: jsonText(json['disclosure']),
        categories: jsonObjects(
          json['categories'],
          PlaceReportCategory.fromJson,
        ),
      );
}

class PlaceReportCategory {
  const PlaceReportCategory({
    required this.category,
    required this.status,
    required this.sourceType,
    required this.sourceLabel,
    required this.latestObservedAt,
    required this.freshnessLabel,
    required this.confidence,
    required this.reportsCount,
    this.reports = const [],
  });

  final String category;
  final String status;
  final String sourceType;
  final String sourceLabel;
  final String latestObservedAt;
  final String freshnessLabel;
  final double confidence;
  final int reportsCount;
  final List<PlaceReportEntry> reports;

  factory PlaceReportCategory.fromJson(Map<String, dynamic> json) =>
      PlaceReportCategory(
        category: jsonText(json['category']),
        status: jsonText(json['status']),
        sourceType: jsonText(json['source_type']),
        sourceLabel: jsonText(json['source_label']),
        latestObservedAt: jsonText(json['latest_observed_at']),
        freshnessLabel: jsonText(json['freshness_label']),
        confidence: jsonDouble(json['confidence']),
        reportsCount: jsonInt(json['reports_count']),
        reports: jsonObjects(json['reports'], PlaceReportEntry.fromJson),
      );
}

class PlaceReportEntry {
  const PlaceReportEntry({
    required this.id,
    required this.observedAt,
    required this.provenance,
    required this.verified,
    required this.confidence,
    this.note,
    this.sourceLabel,
    this.value = const {},
  });

  final String id;
  final String observedAt;
  final String provenance;
  final bool verified;
  final double confidence;
  final String? note;
  final String? sourceLabel;
  final Map<String, dynamic> value;

  factory PlaceReportEntry.fromJson(Map<String, dynamic> json) =>
      PlaceReportEntry(
        id: jsonText(json['id']),
        observedAt: jsonText(json['observed_at']),
        provenance: jsonText(json['provenance'], 'REPORTED'),
        verified: jsonBool(json['verified']),
        confidence: jsonDouble(json['confidence']),
        note: jsonString(json['note']),
        sourceLabel: jsonString(json['source_label']),
        value: jsonMap(json['value']),
      );
}

class AccessStage {
  const AccessStage({
    required this.stage,
    required this.label,
    required this.status,
    this.detail,
    this.source,
  });

  final String stage;
  final String label;
  final String status;
  final String? detail;
  final String? source;

  factory AccessStage.fromJson(Map<String, dynamic> json) => AccessStage(
    stage: jsonText(json['stage']),
    label: jsonText(json['label']),
    status: jsonText(json['status'], 'unknown'),
    detail: jsonString(json['detail']),
    source: jsonString(json['source']),
  );
}

class AccessChain {
  const AccessChain({
    this.stages = const [],
    this.verifiedStages = 0,
    this.reportedBarriers = 0,
    this.unknownStages = 0,
    this.disclosure,
  });

  final List<AccessStage> stages;
  final int verifiedStages;
  final int reportedBarriers;
  final int unknownStages;
  final String? disclosure;

  factory AccessChain.fromJson(Map<String, dynamic> json) {
    final summary = jsonMap(json['summary']);
    return AccessChain(
      stages: jsonObjects(json['stages'], AccessStage.fromJson),
      verifiedStages: jsonInt(summary['verified_stages']),
      reportedBarriers: jsonInt(summary['reported_barriers']),
      unknownStages: jsonInt(summary['unknown_stages']),
      disclosure: jsonString(json['disclosure']),
    );
  }
}

class CrowdBucket {
  const CrowdBucket({
    required this.weekday,
    required this.bucket,
    required this.reports,
    required this.meanLevel,
    required this.latestObservedAt,
  });

  final int weekday;
  final String bucket;
  final int reports;
  final double meanLevel;
  final String latestObservedAt;

  factory CrowdBucket.fromJson(Map<String, dynamic> json) => CrowdBucket(
    weekday: jsonInt(json['weekday']),
    bucket: jsonText(json['bucket']),
    reports: jsonInt(json['reports']),
    meanLevel: jsonDouble(json['mean_level']),
    latestObservedAt: jsonText(json['latest_observed_at']),
  );
}

class CrowdObservation {
  const CrowdObservation({
    required this.reportsSeen,
    required this.reportsUsed,
    required this.latestObservedAt,
    this.excludedStale = 0,
    this.excludedOutliers = 0,
    this.rangeMin,
    this.rangeMax,
    this.buckets = const [],
    this.note,
  });

  final int reportsSeen;
  final int reportsUsed;
  final String latestObservedAt;
  final int excludedStale;
  final int excludedOutliers;
  final double? rangeMin;
  final double? rangeMax;
  final List<CrowdBucket> buckets;
  final String? note;

  factory CrowdObservation.fromJson(Map<String, dynamic> json) {
    final range = jsonMap(json['range']);
    return CrowdObservation(
      reportsSeen: jsonInt(json['reports_seen']),
      reportsUsed: jsonInt(json['reports_used']),
      latestObservedAt: jsonText(json['latest_observed_at']),
      excludedStale: jsonInt(json['excluded_stale']),
      excludedOutliers: jsonInt(json['excluded_outliers']),
      rangeMin: jsonDoubleOrNull(range['min']),
      rangeMax: jsonDoubleOrNull(range['max']),
      buckets: jsonObjects(json['buckets'], CrowdBucket.fromJson),
      note: jsonString(json['note']),
    );
  }
}

class CrowdPoint {
  const CrowdPoint({
    required this.weekday,
    required this.bucket,
    required this.expectedLevel,
    required this.reports,
    this.levelLabel,
    this.spread = 0,
    this.intervalLow,
    this.intervalHigh,
    this.granularity,
    this.fallback = false,
    this.stale = false,
    this.confidence,
    this.confidenceLabel,
    this.meanReportAgeDays,
  });

  final int weekday;
  final String bucket;
  final double expectedLevel;
  final int reports;
  final String? levelLabel;
  final double spread;
  final double? intervalLow;
  final double? intervalHigh;
  final String? granularity;
  final bool fallback;
  final bool stale;
  final double? confidence;
  final String? confidenceLabel;
  final double? meanReportAgeDays;

  factory CrowdPoint.fromJson(Map<String, dynamic> json) {
    final interval = jsonList(json['interval_80']);
    return CrowdPoint(
      weekday: jsonInt(json['weekday']),
      bucket: jsonText(json['bucket']),
      expectedLevel: jsonDouble(json['expected_level']),
      reports: jsonInt(json['reports']),
      levelLabel: jsonString(json['level_label']),
      spread: jsonDouble(json['spread']),
      intervalLow: interval.isNotEmpty ? jsonDoubleOrNull(interval[0]) : null,
      intervalHigh: interval.length > 1 ? jsonDoubleOrNull(interval[1]) : null,
      granularity: jsonString(json['granularity']),
      fallback: jsonBool(json['fallback']),
      stale: jsonBool(json['stale']),
      confidence: jsonDoubleOrNull(json['confidence']),
      confidenceLabel: jsonString(json['confidence_label']),
      meanReportAgeDays: jsonDoubleOrNull(json['mean_report_age_days']),
    );
  }
}

class CrowdPrediction {
  const CrowdPrediction({
    required this.provenance,
    this.method,
    this.model,
    this.note,
    this.forecasts = const [],
  });

  final String provenance;
  final String? method;
  final String? model;
  final String? note;
  final List<CrowdPoint> forecasts;

  factory CrowdPrediction.fromJson(Map<String, dynamic> json) =>
      CrowdPrediction(
        provenance: jsonText(json['provenance'], 'PREDICTED'),
        method: jsonString(json['method']),
        model: jsonString(json['model']),
        note: jsonString(json['note']),
        forecasts: jsonObjects(json['forecasts'], CrowdPoint.fromJson),
      );
}

class CrowdForecast {
  const CrowdForecast({
    required this.status,
    this.model,
    this.message,
    this.reason,
    this.requiredReports,
    this.availableReports,
    this.observed,
    this.latestObservationAt,
    this.latestObservationSource,
    this.latestObservationValue = const {},
    this.predicted,
    this.disclosure,
  });

  final String status;
  final String? model;
  final String? message;
  final String? reason;
  final int? requiredReports;
  final int? availableReports;
  final CrowdObservation? observed;
  final String? latestObservationAt;
  final String? latestObservationSource;
  final Map<String, dynamic> latestObservationValue;
  final CrowdPrediction? predicted;
  final String? disclosure;

  bool get hasData => status == 'ok' || status == 'insufficient_data';

  factory CrowdForecast.fromJson(Map<String, dynamic> json) {
    final observedJson = jsonMap(json['observed']);
    final predictedJson = jsonMap(json['predicted']);
    final latest = jsonMap(json['latest_observation']);
    return CrowdForecast(
      status: jsonText(json['status'], 'insufficient_data'),
      model: jsonString(json['model']),
      message: jsonString(json['message']),
      reason: jsonString(json['reason']),
      requiredReports: jsonIntOrNull(json['required_reports']),
      availableReports: jsonIntOrNull(json['available_reports']),
      observed: observedJson.isEmpty
          ? null
          : CrowdObservation.fromJson(observedJson),
      latestObservationAt: jsonString(latest['observed_at']),
      latestObservationSource: jsonString(latest['source_label']) ??
          jsonString(latest['source_type']),
      latestObservationValue: jsonMap(latest['value']),
      predicted: predictedJson.isEmpty
          ? null
          : CrowdPrediction.fromJson(predictedJson),
      disclosure: jsonString(json['disclosure']),
    );
  }
}

class PlaceDetail {
  const PlaceDetail({
    required this.activity,
    required this.catalogFreshness,
    required this.reports,
    this.accessChain,
    this.crowdForecast,
    this.unknowns = const [],
    this.evidenceDisclosure,
  });

  final Activity activity;
  final CatalogFreshness catalogFreshness;
  final PlaceReportAggregate reports;
  final AccessChain? accessChain;
  final CrowdForecast? crowdForecast;
  final List<String> unknowns;
  final String? evidenceDisclosure;

  factory PlaceDetail.fromJson(Map<String, dynamic> json) {
    final evidence = jsonMap(json['evidence']);
    final chain = jsonMap(json['access_chain']);
    final forecast = jsonMap(json['crowd_forecast']);
    return PlaceDetail(
      activity: Activity.fromJson(jsonMap(json['activity'])),
      catalogFreshness: CatalogFreshness.fromJson(
        jsonMap(json['catalog_freshness']),
      ),
      reports: PlaceReportAggregate.fromJson(jsonMap(json['reports'])),
      accessChain: chain.isEmpty ? null : AccessChain.fromJson(chain),
      crowdForecast: forecast.isEmpty
          ? null
          : CrowdForecast.fromJson(forecast),
      unknowns: jsonStringList(evidence['unknowns']),
      evidenceDisclosure: jsonString(evidence['disclosure']),
    );
  }
}

class NearbyBase {
  const NearbyBase({
    required this.lat,
    required this.lon,
    required this.source,
  });

  final double lat;
  final double lon;
  final String source;

  factory NearbyBase.fromJson(Map<String, dynamic> json) => NearbyBase(
    lat: jsonDouble(json['lat']),
    lon: jsonDouble(json['lon']),
    source: jsonText(json['source'], 'shared trip base'),
  );
}

class NearbyItem {
  const NearbyItem({
    required this.activity,
    required this.distanceKm,
    required this.travelMinutes,
    required this.provenance,
  });

  final Activity activity;
  final double distanceKm;
  final int travelMinutes;
  final String provenance;

  factory NearbyItem.fromJson(Map<String, dynamic> json) => NearbyItem(
    activity: Activity.fromJson(jsonMap(json['activity'])),
    distanceKm: jsonDouble(json['distance_km']),
    travelMinutes: jsonInt(json['travel_minutes']),
    provenance: jsonText(json['provenance'], 'ESTIMATED'),
  );
}

class NearbyResponse {
  const NearbyResponse({
    required this.base,
    required this.radiusKm,
    required this.items,
    required this.disclosure,
  });

  final NearbyBase base;
  final double radiusKm;
  final List<NearbyItem> items;
  final String disclosure;

  factory NearbyResponse.fromJson(Map<String, dynamic> json) => NearbyResponse(
    base: NearbyBase.fromJson(jsonMap(json['base'])),
    radiusKm: jsonDouble(json['radius_km']),
    items: jsonObjects(json['items'], NearbyItem.fromJson),
    disclosure: jsonText(json['disclosure']),
  );
}

class ExpectationEvidence {
  const ExpectationEvidence({
    required this.item,
    required this.status,
    required this.detail,
  });

  final String item;
  final String status;
  final String detail;

  factory ExpectationEvidence.fromJson(Map<String, dynamic> json) =>
      ExpectationEvidence(
        item: jsonText(json['item']),
        status: jsonText(json['status'], 'UNKNOWN'),
        detail: jsonText(json['detail']),
      );
}

class ExpectationCheck {
  const ExpectationCheck({
    required this.activityId,
    required this.claim,
    required this.evidence,
    required this.recentReports,
    required this.limitations,
    required this.unknowns,
    required this.verdict,
  });

  final String activityId;
  final String claim;
  final List<ExpectationEvidence> evidence;
  final List<PlaceReportCategory> recentReports;
  final List<String> limitations;
  final List<String> unknowns;
  final String verdict;

  factory ExpectationCheck.fromJson(Map<String, dynamic> json) =>
      ExpectationCheck(
        activityId: jsonText(json['activity_id']),
        claim: jsonText(json['claim']),
        evidence: jsonObjects(json['evidence'], ExpectationEvidence.fromJson),
        recentReports: jsonObjects(
          json['recent_reports'],
          PlaceReportCategory.fromJson,
        ),
        limitations: jsonStringList(json['limitations']),
        unknowns: jsonStringList(json['unknowns']),
        verdict: jsonText(json['verdict'], 'insufficient_evidence'),
      );
}

class ContributorRegistration {
  const ContributorRegistration({
    required this.id,
    required this.destinationId,
    required this.acceptsRequests,
    required this.verified,
    required this.note,
  });

  final String id;
  final String destinationId;
  final bool acceptsRequests;
  final bool verified;
  final String note;

  factory ContributorRegistration.fromJson(Map<String, dynamic> json) =>
      ContributorRegistration(
        id: jsonText(json['id']),
        destinationId: jsonText(json['destination_id']),
        acceptsRequests: jsonBool(json['accepts_requests']),
        verified: jsonBool(json['verified']),
        note: jsonText(json['note']),
      );
}
