import 'package:dio/dio.dart';

import '../models/json.dart';
import '../models/memories.dart';
import '../models/monitoring.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

class MemoryRepository {
  MemoryRepository(this._api);

  final ApiClient _api;

  Future<MemoriesResponse> list(String tripId) async =>
      MemoriesResponse.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/memories')),
      );

  Future<Memory> create(
    String tripId, {
    required String text,
    String visibility = 'trip',
    String kind = 'text',
    String? caption,
    String? mediaUrl,
    String? mediaType,
  }) async => Memory.fromJson(
    jsonMap(
      await _api.post(
        '/api/trips/$tripId/memories',
        data: {
          'kind': kind,
          'text_content': text,
          'visibility': visibility,
          if (caption != null && caption.isNotEmpty) 'caption': caption,
          if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
          if (mediaType != null && mediaType.isNotEmpty) 'media_type': mediaType,
        },
      ),
    ),
  );

  /// Uploads media (photo, video, voice) and returns the server-issued media URL.
  Future<String> uploadMedia(
    String tripId, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final data = await _api.upload(
      '/api/trips/$tripId/media',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    final url = jsonString(data['media_url']);
    if (url == null || url.isEmpty) {
      throw ApiException(
        message: 'The upload finished without a media URL.',
        statusCode: 502,
      );
    }
    return url;
  }

  Future<void> update(
    String tripId,
    String memoryId,
    Map<String, dynamic> changes,
  ) async {
    await _api.patch('/api/trips/$tripId/memories/$memoryId', data: changes);
  }

  Future<void> delete(String tripId, String memoryId) async {
    await _api.delete('/api/trips/$tripId/memories/$memoryId');
  }

  Future<Studio> studio(String tripId) async =>
      Studio.fromJson(jsonMap(await _api.get('/api/trips/$tripId/memory-studio')));

  Future<List<StudioEvent>> suggestEvents(String tripId) async {
    final data = jsonMap(
      await _api.post('/api/trips/$tripId/memory-studio/suggest-events'),
    );
    return jsonObjects(data['created'], StudioEvent.fromJson);
  }

  Future<void> approveEvent(String tripId, String eventId) async {
    await _api.post('/api/trips/$tripId/memory-events/$eventId/approve');
  }

  Future<ReplayResponse> replay(String tripId) async =>
      ReplayResponse.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/replay')),
      );

  Future<String> travelBook(String tripId) async =>
      (await _api.get('/api/trips/$tripId/travel-book', raw: true)).toString();

  Future<OfflineSnapshot> offlineSnapshot(String tripId) async =>
      OfflineSnapshot.fromJson(
        jsonMap(await _api.get('/api/trips/$tripId/offline')),
      );

  Future<List<SyncQueueEntry>> syncQueue(String tripId) async {
    final data = await _api.get('/api/trips/$tripId/sync');
    final raw = data is Map ? data['items'] : data;
    return jsonObjects(raw, SyncQueueEntry.fromJson);
  }

  Future<SyncOutcome> sync(String tripId, List<Map<String, dynamic>> items) async =>
      SyncOutcome.fromJson(
        jsonMap(await _api.post('/api/trips/$tripId/sync', data: items)),
      );
}
