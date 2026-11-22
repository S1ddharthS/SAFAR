import '../models/json.dart';
import '../models/social.dart';
import '../network/api_client.dart';

class SocialRepository {
  SocialRepository(this._api);

  final ApiClient _api;

  Future<SerendipityFeed> feed() async =>
      SerendipityFeed.fromJson(jsonMap(await _api.get('/api/serendipity/matches')));

  Future<List<TravellerMatch>> matches() async {
    final data = jsonMap(await _api.get('/api/serendipity/matches'));
    final raw = data['matches'];
    return jsonObjects(raw, TravellerMatch.fromJson);
  }

  Future<List<ConnectionRequestItem>> requests() async {
    final data = await _api.get('/api/serendipity/requests');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, ConnectionRequestItem.fromJson);
  }

  Future<void> requestConnection({
    required String toUserId,
    String? tripId,
    String? message,
  }) async {
    await _api.post(
      '/api/serendipity/requests',
      data: {
        'to_user_id': toUserId,
        'trip_id': ?tripId,
        if (message != null && message.isNotEmpty) 'message': message,
      },
    );
  }

  Future<void> decideConnection(String id, {required bool accept}) async {
    await _api.post(
      '/api/serendipity/requests/$id/decide',
      data: {'accept': accept},
    );
  }

  Future<void> blockUser(String userId) async {
    await _api.post('/api/users/me/blocks/$userId');
  }

  Future<void> unblockUser(String userId) async {
    await _api.delete('/api/users/me/blocks/$userId');
  }
}
