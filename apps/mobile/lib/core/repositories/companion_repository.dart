import '../models/json.dart';
import '../models/monitoring.dart';
import '../network/api_client.dart';

class CompanionRepository {
  CompanionRepository(this._api);

  final ApiClient _api;

  Future<List<CompanionLink>> list(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/companion-links');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, CompanionLink.fromJson);
  }

  Future<CompanionLinkCreated> create(
    String tripId, {
    required String purpose,
    required String targetId,
    int ttlMinutes = 1440,
  }) async => CompanionLinkCreated.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/companion-links',
        data: {
          'purpose': purpose,
          'target_id': targetId,
          'ttl_minutes': ttlMinutes,
        },
      ),
    ),
  );

  Future<void> revoke(String tripId, String linkId) async {
    await _api.post('/api/trips/$tripId/companion-links/$linkId/revoke');
  }

  Future<CompanionResponses> responses(String tripId, String linkId) async =>
      CompanionResponses.fromJson(
        jsonMap(
          await _api.get(
            '/api/trips/$tripId/companion-links/$linkId/responses',
          ),
        ),
      );

  /// Public companion endpoints: the token is the credential, no session.
  Future<CompanionContext> publicView(String token) async =>
      CompanionContext.fromJson(
        jsonMap(await _api.get('/api/companion/$token')),
      );

  Future<Map<String, dynamic>> respondPublic(
    String token, {
    required String value,
    String? comment,
  }) async => jsonMap(
    await _api.post(
      '/api/companion/$token/respond',
      data: {'value': value, 'comment': ?comment},
    ),
  );
}
