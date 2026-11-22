import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small key/value contract shared by the cookie jar and the offline queue.
///
/// Only serialised strings are stored. Implementations must never log key or
/// value contents: refresh cookies and offline capture text can be private.
abstract class JsonStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Process-local store used by tests and by the browser verification build,
/// where the browser owns cookies and nothing sensitive should be persisted.
class MemoryJsonStore implements JsonStore {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

/// Device store backed by the platform keystore/keychain.
///
/// Used on native clients so the HttpOnly refresh cookie and queued captures
/// survive an app restart without landing in plaintext preferences.
class SecureJsonStore implements JsonStore {
  SecureJsonStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
