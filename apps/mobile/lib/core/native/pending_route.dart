/// A deep-link target that arrived before the user was signed in.
///
/// GoRouter's redirect sends signed-out visitors to `/login`; after sign-in the
/// router hands this path back once so an invitation link still lands on the
/// invitation instead of the dashboard.
class PendingRoute {
  PendingRoute._();

  static String? _value;

  static void set(String path) => _value = path;

  static String? take(String? fallback) {
    final value = _value;
    _value = null;
    return value ?? fallback;
  }

  static void clear() => _value = null;
}
