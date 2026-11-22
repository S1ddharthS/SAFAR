/// Maps an incoming link to a SAFAR route.
///
/// Supported forms:
/// - `safar://companion/<token>` (custom scheme registered by the app)
/// - `safar://invite/<token>` (trip invitation, single use)
/// - `https://<any-host>/companion/<token>` (universal/app link when a
///   deployment verifies its own domain)
/// - `https://<any-host>/invite/<token>` (the web fallback pages)
///
/// The companion token is the only credential, so any host may forward to it.
String? companionPathFromUri(Uri uri) {
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (uri.scheme == 'safar' && uri.host == 'companion') {
    if (segments.length == 1) return '/companion/${segments.first}';
    return null;
  }
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    if (segments.length == 2 && segments.first == 'companion') {
      return '/companion/${segments[1]}';
    }
  }
  return null;
}

String? invitationPathFromUri(Uri uri) {
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (uri.scheme == 'safar' && (uri.host == 'invite' || uri.host == 'invitation')) {
    if (segments.isEmpty) return null;
    return '/invite/${segments.first}';
  }
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    if (segments.length == 2 && segments.first == 'invite') {
      return '/invite/${segments[1]}';
    }
  }
  return null;
}

/// Resolves any supported SAFAR link to an in-app route.
String? appPathFromUri(Uri uri) =>
    companionPathFromUri(uri) ?? invitationPathFromUri(uri);
