import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState(this.status, {this.me, this.error});

  final AuthStatus status;
  final Me? me;
  final String? error;

  bool get signedIn => status == AuthStatus.signedIn;
  bool get signedOut => status == AuthStatus.signedOut;

  User? get user => me?.user;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState(AuthStatus.unknown)) {
    final api = _ref.read(apiClientProvider);
    api.onUnauthorized = () {
      if (!mounted) return;
      state = const AuthState(AuthStatus.signedOut);
      _ref.invalidate(meProvider);
    };
    bootstrap();
  }

  final Ref _ref;

  Future<void> bootstrap() async {
    if (state.signedIn) return;
    state = const AuthState(AuthStatus.unknown);
    try {
      final me = await _ref.read(authRepositoryProvider).restore();
      if (!mounted) return;
      state = me == null
          ? const AuthState(AuthStatus.signedOut)
          : AuthState(AuthStatus.signedIn, me: me);
    } on ApiException catch (error) {
      if (!mounted) return;
      state = AuthState(AuthStatus.unknown, error: error.message);
    } on Object {
      if (!mounted) return;
      state = const AuthState(
        AuthStatus.unknown,
        error: 'Could not reach SAFAR. Check that the API is running.',
      );
    }
  }

  Future<void> login({required String email, required String password}) async {
    final me = await _ref
        .read(authRepositoryProvider)
        .login(email: email, password: password);
    _clearCachedSessionData();
    state = AuthState(AuthStatus.signedIn, me: me);
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final me = await _ref
        .read(authRepositoryProvider)
        .register(email: email, password: password, displayName: displayName);
    _clearCachedSessionData();
    state = AuthState(AuthStatus.signedIn, me: me);
  }

  Future<void> logout() async {
    await _ref.read(authRepositoryProvider).logout();
    // Flipping to signed-out first lets the router unmount trip screens before
    // anything could refetch with a cleared session.
    state = const AuthState(AuthStatus.signedOut);
  }

  /// Providers are not auto-disposed, so without this a failed or another
  /// person's request stays cached across the sign-in boundary.
  void _clearCachedSessionData() {
    for (final provider in sessionDataProviders) {
      _ref.invalidate(provider);
    }
  }

  Future<void> reload() async {
    final me = await _ref.read(userRepositoryProvider).me();
    if (!mounted) return;
    state = AuthState(AuthStatus.signedIn, me: me);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>(AuthController.new);
