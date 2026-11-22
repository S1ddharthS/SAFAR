import '../models/discovery.dart';
import '../models/json.dart';
import '../models/social.dart';
import '../network/api_client.dart';

class DiscoveryRepository {
  DiscoveryRepository(this._api);

  final ApiClient _api;

  Future<List<Destination>> destinations() async {
    final data = await _api.get('/api/destinations');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Destination.fromJson);
  }

  Future<DestinationDetail> destination(String id) async =>
      DestinationDetail.fromJson(
        jsonMap(await _api.get('/api/destinations/$id')),
      );

  Future<SearchResult> search({
    required String destinationId,
    String? query,
    String lens = 'balanced',
    double? maxBudget,
    int? maxDuration,
    bool indoor = false,
    bool accessible = false,
    String? tags,
    int limit = 30,
  }) async => SearchResult.fromJson(
    jsonMap(
      await _api.get(
        '/api/activities/search',
        query: {
          'destination_id': destinationId,
          if (query != null && query.isNotEmpty) 'q': query,
          'lens': lens,
          'max_budget': ?maxBudget,
          'max_duration': ?maxDuration,          if (indoor) 'indoor': true,
          if (accessible) 'accessible': true,
          if (tags != null && tags.isNotEmpty) 'tags': tags,
          'limit': limit,
        },
      ),
    ),
  );

  Future<PlaceDetail> placeDetail(String tripId, String activityId) async =>
      PlaceDetail.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/places/$activityId')),
      );

  Future<List<PlaceReportItem>> placeReports(
    String tripId, {
    required String activityId,
    int days = 90,
  }) async {
    final data = await _api.get(
      '/api/trips/$tripId/place-reports',
      query: {'activity_id': activityId, 'days': days},
    );
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, PlaceReportItem.fromJson);
  }

  Future<void> createPlaceReport(
    String tripId, {
    required String activityId,
    required String category,
    required Map<String, dynamic> value,
    String? note,
  }) async {
    await _api.post(
      '/api/trips/$tripId/place-reports',
      data: {
        'activity_id': activityId,
        'category': category,
        'value': value,
        if (note != null && note.isNotEmpty) 'note': note,
        'source_type': 'community',
      },
    );
  }

  Future<void> markReportHelpful(String tripId, String reportId) async {
    await _api.post('/api/trips/$tripId/place-reports/$reportId/helpful');
  }

  Future<ExpectationCheck> expectationCheck(
    String tripId,
    String activityId,
    String claim,
  ) async => ExpectationCheck.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/places/$activityId/expectation',
        data: {'claim': claim},
      ),
    ),
  );

  Future<NearbyResponse> nearby(
    String tripId, {
    double? lat,
    double? lon,
    double radiusKm = 5,
    String? category,
    int limit = 20,
  }) async => NearbyResponse.fromJson(
    jsonMap(
      await _api.get(
        '/api/trips/$tripId/nearby',
        query: {
          'lat': ?lat,
          'lon': ?lon,
          'radius_km': radiusKm,
          'category': ?category,
          'limit': limit,
        },
      ),
    ),
  );

  Future<List<Circle>> circles() async {
    final data = await _api.get('/api/circles');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Circle.fromJson);
  }

  Future<CircleDetail> circle(String id) async =>
      CircleDetail.fromJson(jsonMap(await _api.get('/api/circles/$id')));

  Future<void> joinCircle(String id) async {
    await _api.post('/api/circles/$id/join');
  }

  Future<void> leaveCircle(String id) async {
    await _api.delete('/api/circles/$id/join');
  }

  Future<void> postToCircle(
    String id, {
    required String title,
    required String body,
    String? activityId,
  }) async {
    await _api.post(
      '/api/circles/$id/posts',
      data: {'title': title, 'body': body, 'activity_id': ?activityId},
    );
  }

  Future<List<Contributor>> contributors({String? destinationId}) async {
    final data = await _api.get(
      '/api/contributors',
      query: destinationId == null ? null : {'destination_id': destinationId},
    );
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Contributor.fromJson);
  }

  Future<ContributorRegistration> upsertContributor({
    required String destinationId,
    String? bio,
    List<String> expertise = const [],
    bool acceptsRequests = true,
  }) async => ContributorRegistration.fromJson(
    jsonMap(
      await _api.post(
        '/api/contributors',
        data: {
          'destination_id': destinationId,
          if (bio != null && bio.isNotEmpty) 'bio': bio,
          'expertise': expertise,
          'accepts_requests': acceptsRequests,
        },
      ),
    ),
  );
}
