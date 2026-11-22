import '../models/itinerary.dart';
import '../models/json.dart';
import '../models/planning.dart';
import '../network/api_client.dart';

class ItineraryRepository {
  ItineraryRepository(this._api);

  final ApiClient _api;

  Future<Itinerary> get(String tripId) async =>
      Itinerary.fromJson(jsonMap(await _api.get('/api/trips/$tripId/itinerary')));

  Future<void> addItem(
    String tripId, {
    required String day,
    required String title,
    String startTime = '09:00',
    String? endTime,
    String? activityId,
    String? notes,
    double? costEstimate,
    bool isProtected = false,
  }) async {
    await _api.post(
      '/api/trips/$tripId/itinerary/items',
      data: {
        'day': day,
        'start_time': startTime,
        'end_time': endTime,
        'title': title,
        'activity_id': ?activityId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'cost_estimate': ?costEstimate,
        'is_protected': isProtected,
      },
    );
  }

  Future<void> updateItem(
    String tripId,
    String itemId,
    Map<String, dynamic> changes,
  ) async {
    await _api.patch('/api/trips/$tripId/itinerary/items/$itemId', data: changes);
  }

  Future<void> deleteItem(String tripId, String itemId) async {
    await _api.delete('/api/trips/$tripId/itinerary/items/$itemId');
  }

  Future<void> setAttendance(
    String tripId,
    String itemId,
    String status,
  ) async {
    await _api.post(
      '/api/trips/$tripId/itinerary/items/$itemId/attendance',
      data: {'status': status},
    );
  }

  Future<List<Proposal>> proposals(String tripId, {String status = 'all'}) async {
    final data = await _api.get(
      '/api/trips/$tripId/proposals',
      query: {'status': status},
    );
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, Proposal.fromJson);
  }

  Future<Proposal> createProposal(
    String tripId, {
    required String title,
    String kind = 'add_activity',
    String? summary,
    String? activityId,
    String? day,
    String? startTime,
    String? targetItemId,
  }) async => Proposal.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/proposals',
        data: {
          'kind': kind,
          'title': title,
          if (summary != null && summary.isNotEmpty) 'summary': summary,
          'activity_id': ?activityId,
          'day': ?day,
          'start_time': ?startTime,
          'target_item_id': ?targetItemId,
        },
      ),
    ),
  );

  Future<void> vote(
    String tripId,
    String proposalId,
    String value, {
    String? comment,
  }) async {
    await _api.post(
      '/api/trips/$tripId/proposals/$proposalId/vote',
      data: {'value': value, 'comment': ?comment},
    );
  }

  Future<void> approve(String tripId, String proposalId) async {
    await _api.post(
      '/api/trips/$tripId/proposals/$proposalId/approve',
      data: {'approval': true},
    );
  }

  Future<void> reject(String tripId, String proposalId) async {
    await _api.post('/api/trips/$tripId/proposals/$proposalId/reject');
  }

  Future<void> withdraw(String tripId, String proposalId) async {
    await _api.post('/api/trips/$tripId/proposals/$proposalId/withdraw');
  }

  Future<Proposal> getProposal(String tripId, String proposalId) async =>
      Proposal.fromJson(
        jsonMap(
          await _api.get('/api/trips/$tripId/proposals/$proposalId'),
        ),
      );

  Future<EffortBudget> effort(String tripId) async => EffortBudget.fromJson(
    jsonMap(await _api.get('/api/trips/$tripId/effort')),
  );

  Future<FragilityReport> fragility(String tripId) async =>
      FragilityReport.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/fragility')),
      );

  Future<DominoMap> domino(
    String tripId, {
    required String itemId,
    int delayMinutes = 45,
  }) async => DominoMap.fromJson(
    jsonMap(
      await _api.get(
        '/api/trips/$tripId/domino',
        query: {'item_id': itemId, 'delay_minutes': delayMinutes},
      ),
    ),
  );

  Future<List<ShadowplanItem>> shadowplans(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/shadowplans');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, ShadowplanItem.fromJson);
  }

  Future<void> createShadowplan(
    String tripId, {
    required String itemId,
    required String backupActivityId,
    String? notes,
  }) async {
    await _api.post(
      '/api/trips/$tripId/shadowplans',
      data: {
        'item_id': itemId,
        'backup_activity_id': backupActivityId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
  }
}
