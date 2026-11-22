import '../models/inspirations.dart';
import '../models/json.dart';
import '../network/api_client.dart';

class InspirationRepository {
  InspirationRepository(this._api);

  final ApiClient _api;

  Future<List<InspirationItem>> list(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/inspirations');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, InspirationItem.fromJson);
  }

  Future<InspirationItem> create(
    String tripId, {
    required String content,
    String sourceType = 'text',
    String? mediaUrl,
  }) async {
    final data = jsonMap(
      await _api.post(
        '/api/trips/$tripId/inspirations',
        data: {
          'source_type': sourceType,
          'content': content,
          if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
        },
      ),
    );
    return InspirationItem(
      id: jsonText(data['id']),
      sourceType: jsonText(data['source_type'], sourceType),
      content: content,
      status: jsonText(data['status'], 'extracted'),
      extracted: InspirationExtraction.fromJson(jsonMap(data['extraction'])),
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  Future<InspirationExtraction> review(
    String tripId,
    String inspirationId, {
    required String candidateId,
    required String decision,
  }) async {
    final data = jsonMap(
      await _api.post(
        '/api/trips/$tripId/inspirations/$inspirationId/review',
        data: {'candidate_id': candidateId, 'decision': decision},
      ),
    );
    return InspirationExtraction.fromJson(jsonMap(data['extraction']));
  }
}
