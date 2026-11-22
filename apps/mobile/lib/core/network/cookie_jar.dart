import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';

import '../storage/json_store.dart';

const _storageKey = 'safar_cookie_jar_v1';

class _StoredCookie {
  _StoredCookie({
    required this.name,
    required this.value,
    required this.host,
    required this.domain,
    required this.path,
    required this.expiresAt,
    required this.secure,
    required this.httpOnly,
  });

  final String name;
  final String value;
  final String host;
  final String? domain;
  final String path;
  final int? expiresAt;
  final bool secure;
  final bool httpOnly;

  String get key => '${domain ?? host}|$path|$name';

  bool get isExpired =>
      expiresAt != null && DateTime.now().millisecondsSinceEpoch >= expiresAt!;

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'host': host,
    'domain': domain,
    'path': path,
    'expiresAt': expiresAt,
    'secure': secure,
    'httpOnly': httpOnly,
  };

  factory _StoredCookie.fromJson(Map<String, dynamic> json) => _StoredCookie(
    name: (json['name'] ?? '') as String,
    value: (json['value'] ?? '') as String,
    host: (json['host'] ?? '') as String,
    domain: json['domain'] as String?,
    path: (json['path'] ?? '/') as String,
    expiresAt: (json['expiresAt'] as num?)?.toInt(),
    secure: json['secure'] == true,
    httpOnly: json['httpOnly'] == true,
  );

  Cookie toCookie() {
    final cookie = Cookie(name, value)
      ..path = path
      ..secure = secure
      ..httpOnly = httpOnly;
    if (domain != null) cookie.domain = domain;
    if (expiresAt != null) {
      cookie.expires = DateTime.fromMillisecondsSinceEpoch(expiresAt!);
    }
    return cookie;
  }
}

/// A cookie jar that keeps the refresh token across app restarts.
///
/// The backend rotates the refresh token and only accepts it from the
/// `safar_refresh` cookie scoped to `/api/auth`. Access and CSRF tokens stay in
/// memory; only cookies are persisted, and only in secure storage.
class SafarCookieJar implements CookieJar {
  SafarCookieJar(this._store);

  final JsonStore _store;
  final Map<String, _StoredCookie> _cookies = {};
  bool _loaded = false;

  @override
  bool get ignoreExpires => false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await _store.read(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final cookie = _StoredCookie.fromJson(entry);
        if (cookie.name.isEmpty || cookie.isExpired) continue;
        _cookies[cookie.key] = cookie;
      }
    } on FormatException {
      await _store.delete(_storageKey);
    }
  }

  Future<void> _persist() async {
    final live = _cookies.values.where((cookie) => !cookie.isExpired).toList();
    _cookies
      ..clear()
      ..addEntries(live.map((cookie) => MapEntry(cookie.key, cookie)));
    await _store.write(
      _storageKey,
      jsonEncode(live.map((cookie) => cookie.toJson()).toList()),
    );
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) async {
    final now = DateTime.now();
    for (final cookie in cookies) {
      final path = cookie.path?.isNotEmpty == true ? cookie.path! : '/';
      int? expiresAt;
      final maxAge = cookie.maxAge;
      if (maxAge != null) {
        if (maxAge <= 0) {
          _cookies.remove('${cookie.domain ?? uri.host}|$path|${cookie.name}');
          continue;
        }
        expiresAt = now.add(Duration(seconds: maxAge)).millisecondsSinceEpoch;
      } else if (cookie.expires != null) {
        expiresAt = cookie.expires!.millisecondsSinceEpoch;
      }
      final stored = _StoredCookie(
        name: cookie.name,
        value: cookie.value,
        host: uri.host,
        domain: cookie.domain,
        path: path,
        expiresAt: expiresAt,
        secure: cookie.secure,
        httpOnly: cookie.httpOnly,
      );
      if (stored.isExpired) {
        _cookies.remove(stored.key);
      } else {
        _cookies[stored.key] = stored;
      }
    }
    await _persist();
  }

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    await load();
    final matches = _cookies.values
        .where(
          (cookie) =>
              _domainMatches(uri.host, cookie) &&
              _pathMatches(uri.path, cookie.path) &&
              (!cookie.secure || uri.scheme == 'https') &&
              !cookie.isExpired,
        )
        .toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    return matches.map((cookie) => cookie.toCookie()).toList();
  }

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) async {
    _cookies.removeWhere((_, cookie) {
      if (cookie.domain == null) return cookie.host == uri.host;
      return withDomainSharedCookie && _domainMatches(uri.host, cookie);
    });
    await _persist();
  }

  @override
  Future<void> deleteAll() async {
    _cookies.clear();
    await _store.delete(_storageKey);
  }

  static bool _domainMatches(String host, _StoredCookie cookie) {
    final domain = cookie.domain;
    if (domain == null || domain.isEmpty) return host == cookie.host;
    final normalised = domain.startsWith('.') ? domain.substring(1) : domain;
    return host == normalised || host.endsWith('.$normalised');
  }

  static bool _pathMatches(String requestPath, String cookiePath) {
    final path = cookiePath.isEmpty ? '/' : cookiePath;
    if (requestPath == path) return true;
    if (!requestPath.startsWith(path)) return false;
    if (path.endsWith('/')) return true;
    return requestPath.length > path.length &&
        requestPath[path.length] == '/';
  }
}
