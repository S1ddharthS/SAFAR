import '../models/common.dart';
import '../models/json.dart';
import '../models/social.dart';
import '../network/api_client.dart';

class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  Future<Me> me() async =>
      Me.fromJson(jsonMap(await _api.get('/api/users/me')));

  Future<Profile> updateProfile(Map<String, dynamic> changes) async =>
      Profile.fromJson(jsonMap(await _api.patch('/api/users/me/profile', data: changes)));

  Future<Dna> updateDna(Map<String, int> scores) async =>
      Dna.fromJson(jsonMap(await _api.put('/api/users/me/dna', data: {'scores': scores})));

  Future<Map<String, dynamic>> updateConsents(Map<String, bool> consents) async =>
      jsonMap(await _api.put('/api/users/me/consents', data: {'consents': consents}));

  Future<User> updateSettings(Map<String, dynamic> changes) async =>
      User.fromJson(jsonMap(await _api.patch('/api/users/me/settings', data: changes)));

  Future<NotificationFeed> notifications() async =>
      NotificationFeed.fromJson(jsonMap(await _api.get('/api/users/me/notifications')));

  Future<void> markRead(String id) async {
    await _api.post('/api/users/me/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _api.post('/api/users/me/notifications/read-all');
  }

  Future<ThreadResponse> thread() async =>
      ThreadResponse.fromJson(jsonMap(await _api.get('/api/users/me/thread')));

  Future<String> exportData() async =>
      (await _api.get('/api/users/me/export', raw: true)).toString();

  Future<void> deleteAccount() async {
    await _api.delete('/api/users/me');
  }
}
