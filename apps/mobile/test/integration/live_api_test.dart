// Live API integration tests for the Flutter networking layer.
//
// These exercise the real FastAPI session model (HttpOnly cookies, CSRF,
// refresh rotation and revocation) through [ApiClient] and [SafarCookieJar].
// They are skipped unless SAFAR_LIVE_API points at a running instance:
//
//   SAFAR_LIVE_API=http://localhost:8020 flutter test test/integration
//
// The seeded demo account is required, so run against a seeded database.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar_mobile/core/network/api_client.dart';
import 'package:safar_mobile/core/network/api_exception.dart';
import 'package:safar_mobile/core/network/cookie_jar.dart';
import 'package:safar_mobile/core/repositories/auth_repository.dart';
import 'package:safar_mobile/core/storage/json_store.dart';

const _email = 'mira@safar.demo';
const _password = 'safar-demo-123';

final _baseUrl = Platform.environment['SAFAR_LIVE_API'];
final _skipReason = _baseUrl == null
    ? 'Set SAFAR_LIVE_API=http://localhost:8020 to run live API tests'
    : null;

({ApiClient api, SafarCookieJar jar}) _buildClient(
  MemoryJsonStore store, {
  void Function()? onUnauthorized,
}) {
  final jar = SafarCookieJar(store);
  return (
    api: ApiClient(
      baseUrl: _baseUrl!,
      jar: jar,
      store: store,
      onUnauthorized: onUnauthorized,
    ),
    jar: jar,
  );
}

Future<ApiClient> _signedInClient(MemoryJsonStore store) async {
  final client = _buildClient(store).api;
  await AuthRepository(client).login(email: _email, password: _password);
  return client;
}

Future<String?> _refreshToken(SafarCookieJar jar) async {
  final uri = Uri.parse('$_baseUrl/api/auth/refresh');
  for (final cookie in await jar.loadForRequest(uri)) {
    if (cookie.name == 'safar_refresh') return cookie.value;
  }
  return null;
}

void main() {
  group('SAFAR live API session handling', () {
    test('login returns the member and a CSRF token', () async {
      final client = _buildClient(MemoryJsonStore()).api;
      final me = await AuthRepository(client).login(
        email: _email,
        password: _password,
      );
      expect(me.user.email, _email);
      expect(client.accessToken, isNotEmpty);
      expect(client.csrfToken, isNotEmpty);
    });

    test('a persisted refresh cookie restores the session', () async {
      final store = MemoryJsonStore();
      await _signedInClient(store);

      // Simulate an app restart: a fresh client shares only the stored cookies.
      final restored = _buildClient(store).api;
      expect(restored.accessToken, isNull);
      final me = await AuthRepository(restored).restore();
      expect(me, isNotNull);
      expect(me!.user.email, _email);
      expect(restored.accessToken, isNotEmpty);

      final stored = await store.read('safar_cookie_jar_v1');
      expect(stored, isNotNull);
      expect(stored, contains('safar_refresh'));
    });

    test('logout revokes the refresh session server-side', () async {
      final store = MemoryJsonStore();
      final client = await _signedInClient(store);
      await AuthRepository(client).logout();

      final restored = _buildClient(store).api;
      expect(await AuthRepository(restored).restore(), isNull);
      expect(await store.read('safar_cookie_jar_v1'), anyOf(isNull, isEmpty));
    });

    test('a rejected access token refreshes and retries transparently', () async {
      final built = _buildClient(MemoryJsonStore());
      final client = built.api;
      await AuthRepository(client).login(email: _email, password: _password);
      final before = await _refreshToken(built.jar);
      expect(before, isNotNull);

      client.accessToken = 'not-a-real-token';
      final me = await AuthRepository(client).me();
      expect(me.user.email, _email);
      expect(client.accessToken, isNot('not-a-real-token'));

      // The server rotates the refresh token on every successful refresh.
      final after = await _refreshToken(built.jar);
      expect(after, isNotNull);
      expect(after, isNot(before));
    });

    test('cookie-only writes are rejected without a CSRF token', () async {
      final store = MemoryJsonStore();
      final built = _buildClient(store);
      await AuthRepository(built.api).login(
        email: _email,
        password: _password,
      );

      final uri = Uri.parse('$_baseUrl/api/auth/logout');
      final cookies = await built.jar.loadForRequest(uri);
      expect(cookies, isNotEmpty);
      final header = cookies
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');

      final bare = Dio(BaseOptions(baseUrl: _baseUrl!));
      await expectLater(
        bare.post<void>(
          '/api/auth/logout',
          options: Options(headers: {'Cookie': header}),
        ),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status',
            403,
          ),
        ),
      );
    });

    test('wrong credentials surface an unauthorised ApiException', () async {
      final client = _buildClient(MemoryJsonStore()).api;
      await expectLater(
        AuthRepository(client).login(email: _email, password: 'wrong-password'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'status', 401)
              .having((error) => error.isUnauthorized, 'unauthorised', true),
        ),
      );
      expect(client.accessToken, isNull);
    });

    test('an unreachable API reports a network failure', () async {
      final jar = SafarCookieJar(MemoryJsonStore());
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:1',
        jar: jar,
        store: MemoryJsonStore(),
      );
      await expectLater(
        client.get('/api/users/me'),
        throwsA(
          isA<ApiException>().having((error) => error.isNetwork, 'network', true),
        ),
      );
    });
  }, skip: _skipReason);
}
