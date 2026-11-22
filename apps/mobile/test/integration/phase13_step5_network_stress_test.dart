// Phase 13 Step 5: Network Resilience & Failure Handling Test
// Verifies structured error propagation, timeout handling, network loss,
// and session invalidation without application crashes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/network/api_client.dart';
import 'package:safar_mobile/core/network/api_exception.dart';
import 'package:safar_mobile/core/network/cookie_jar.dart';
import 'package:safar_mobile/core/repositories/auth_repository.dart';
import 'package:safar_mobile/core/storage/json_store.dart';

const _miraEmail = 'mira@safar.demo';
const _password = 'safar-demo-123';

final _liveApi = Platform.environment['SAFAR_LIVE_API'];
final _skipLive = _liveApi == null ? 'SAFAR_LIVE_API not set' : null;

void main() {
  group('Phase 13 Step 5: Network Resilience (Live Staging API)', skip: _skipLive, () {
    test('Normal connectivity succeeds; unreachable API surfaces human error without crashing', () async {
      final store = MemoryJsonStore();
      final jar = SafarCookieJar(store);
      final client = ApiClient(
        baseUrl: _liveApi ?? 'http://127.0.0.1:8020',
        jar: jar,
        store: store,
      );

      // Normal connectivity: successful login
      final authRepo = AuthRepository(client);
      final me = await authRepo.login(email: _miraEmail, password: _password);
      expect(me.user.email, _miraEmail);
      expect(client.accessToken, isNotEmpty);

      // Simulate connection loss / unreachable port
      final unreachableClient = ApiClient(
        baseUrl: 'http://127.0.0.1:59999', // invalid/unbound port
        jar: SafarCookieJar(MemoryJsonStore()),
        store: MemoryJsonStore(),
      );
      final unreachableAuth = AuthRepository(unreachableClient);

      expect(
        () => unreachableAuth.login(email: _miraEmail, password: _password),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', null)
              .having((e) => e.message, 'message', contains('reach SAFAR')),
        ),
      );
    });

    test('Temporary connection drop handles retry cleanly after restoration', () async {
      final store = MemoryJsonStore();
      final jar = SafarCookieJar(store);
      final liveUrl = _liveApi ?? 'http://127.0.0.1:8020';

      // 1. Point client initially to an offline/unreachable endpoint
      final client = ApiClient(
        baseUrl: 'http://127.0.0.1:59998',
        jar: jar,
        store: store,
      );

      // Request fails gracefully
      var failed = false;
      try {
        await AuthRepository(client).login(email: _miraEmail, password: _password);
      } on ApiException catch (e) {
        failed = true;
        expect(e.message, contains('reach SAFAR'));
      }
      expect(failed, isTrue);

      // 2. Restore connectivity (point client to live endpoint)
      final restoredClient = ApiClient(
        baseUrl: liveUrl,
        jar: jar,
        store: store,
      );
      final me = await AuthRepository(restoredClient).login(email: _miraEmail, password: _password);
      expect(me.user.email, _miraEmail);
      expect(restoredClient.accessToken, isNotEmpty);
    });

    test('Expired/tampered session surfaces unauthorized ApiException without crash', () async {
      final store = MemoryJsonStore();
      final jar = SafarCookieJar(store);
      final client = ApiClient(
        baseUrl: _liveApi ?? 'http://127.0.0.1:8020',
        jar: jar,
        store: store,
      );

      // Supply invalid access token
      client.accessToken = 'tampered-invalid-jwt-token';
      expect(
        () => client.get('/api/users/me'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });
  });
}
