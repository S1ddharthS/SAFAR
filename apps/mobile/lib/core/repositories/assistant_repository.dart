import '../models/assistant.dart';
import '../models/json.dart';
import '../network/api_client.dart';

class AssistantRepository {
  AssistantRepository(this._api);

  final ApiClient _api;

  Future<AssistantAnswer> chat({
    required String message,
    String? tripId,
    String? language,
  }) async => AssistantAnswer.fromJson(
    jsonMap(
      await _api.post(
        '/api/assistant/chat',
        data: {
          'message': message,
          'trip_id': ?tripId,
          'language': ?language,
        },
      ),
    ),
  );

  Future<AssistantAnswer> tripChat(
    String tripId, {
    required String message,
    String? language,
  }) async => AssistantAnswer.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/assistant',
        data: {
          'message': message,
          'trip_id': tripId,
          'language': ?language,
        },
      ),
    ),
  );

  Future<Map<String, dynamic>> capabilities() async =>
      jsonMap(await _api.get('/api/assistant/capabilities'));
}
