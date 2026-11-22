import '../models/common.dart';
import '../models/json.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<Me> login({required String email, required String password}) async {
    final data = jsonMap(
      await _api.post(
        '/api/auth/login',
        data: {'email': email.trim(), 'password': password},
      ),
    );
    _stashTokens(data);
    return me();
  }

  Future<Me> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final data = jsonMap(
      await _api.post(
        '/api/auth/register',
        data: {
          'email': email.trim(),
          'password': password,
          'display_name': displayName.trim(),
        },
      ),
    );
    _stashTokens(data);
    return me();
  }

  /// Uses the persisted HttpOnly refresh cookie. Returns null when the server
  /// rejects the session, and rethrows network failures so the UI can retry.
  Future<Me?> restore() async {
    final refreshed = await _api.refreshSession();
    if (!refreshed) return null;
    return me();
  }

  Future<Me> me() async {
    final data = await _api.get('/api/users/me');
    return Me.fromJson(jsonMap(data));
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/auth/logout');
    } on ApiException {
      // A revoked or expired session still needs local cleanup.
    } finally {
      await _api.clearSession();
    }
  }

  void _stashTokens(Map<String, dynamic> data) {
    final access = jsonString(data['access_token']);
    final csrf = jsonString(data['csrf_token']);
    if (access == null || access.isEmpty) {
      throw ApiException(message: 'The server did not return a session.');
    }
    _api.accessToken = access;
    _api.csrfToken = csrf;
  }
}
