import '../models/engine.dart';
import '../models/itinerary.dart';
import '../models/json.dart';
import '../models/planning.dart';
import '../network/api_client.dart';

class EngineRepository {
  EngineRepository(this._api);

  final ApiClient _api;

  Future<EngineBatch> latest(String tripId, {String? mode}) async =>
      EngineBatch.fromJson(
        jsonMap(
          await _api.get(
            '/api/trips/$tripId/engine/latest',
            query: mode == null ? null : {'mode': mode},
          ),
        ),
      );

  Future<EngineBatch> recommend(
    String tripId, {
    String mode = 'everyone_wins',
    String? forDate,
    int limit = 6,
  }) async => EngineBatch.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/engine/recommend',
        data: {
          'mode': mode,
          'for_date': ?forDate,
          'limit': limit,
        },
      ),
    ),
  );

  Future<void> feedback(
    String tripId,
    String recommendationId,
    String sentiment,
  ) async {
    await _api.post(
      '/api/trips/$tripId/recommendations/$recommendationId/feedback',
      data: {'sentiment': sentiment, 'consented': true},
    );
  }

  Future<void> propose(
    String tripId,
    String recommendationId, {
    required String day,
    String startTime = '09:00',
  }) async {
    await _api.post(
      '/api/trips/$tripId/recommendations/$recommendationId/propose',
      data: {'day': day, 'start_time': startTime},
    );
  }

  Future<RescueAnalysis> analyzeRescue(
    String tripId, {
    required String kind,
    String? itemId,
    int extraMinutes = 45,
    String? note,
  }) async => RescueAnalysis.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/rescue/analyze',
        data: {
          'kind': kind,
          'item_id': ?itemId,
          'extra_minutes': extraMinutes,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      ),
    ),
  );

  Future<void> proposeRescue(
    String tripId, {
    required String kind,
    required String itemId,
    required String activityId,
    required String day,
    required String startTime,
    int extraMinutes = 45,
    String? note,
  }) async {
    await _api.post(
      '/api/trips/$tripId/rescue/propose',
      data: {
        'kind': kind,
        'extra_minutes': extraMinutes,
        if (note != null && note.isNotEmpty) 'note': note,
        'items': [
          {
            'item_id': itemId,
            'activity_id': activityId,
            'day': day,
            'start_time': startTime,
          },
        ],
      },
    );
  }

  Future<TwinComparison> twinCompare(
    String tripId, {
    required List<String> activityIds,
    String? day,
  }) async => TwinComparison.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/twin/compare',
        data: {'activity_ids': activityIds, 'day': ?day},
      ),
    ),
  );

  Future<Proposal> twinPropose(
    String tripId, {
    required List<String> activityIds,
    String? day,
  }) async => Proposal.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/twin/propose',
        data: {'activity_ids': activityIds, 'day': ?day},
      ),
    ),
  );

  Future<NegotiationResult> negotiate(
    String tripId, {
    required List<String> optionA,
    required List<String> optionB,
    String? forDate,
  }) async => NegotiationResult.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/negotiate',
        data: {
          'option_a': optionA,
          'option_b': optionB,
          'for_date': ?forDate,
        },
      ),
    ),
  );
}
