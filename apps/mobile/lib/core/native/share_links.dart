import 'package:share_plus/share_plus.dart';

import '../config/env.dart';

/// Builds a shareable absolute link from an API-issued path such as
/// `/companion/{token}`. Returns null when no public web origin is configured.
String? absoluteWebLink(String path) {
  final base = Env.webBaseUrl;
  if (base == null || base.isEmpty) return null;
  final trimmed = path.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return trimmed.startsWith('/') ? '$base$trimmed' : '$base/$trimmed';
}

/// Opens the platform share sheet. Returns false when sharing is unavailable
/// on this platform so callers can fall back to copying the link.
Future<bool> shareLink({
  required String url,
  required String subject,
  String? message,
}) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: message == null || message.isEmpty ? url : '$message\n$url',
        subject: subject,
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  } on Object {
    return false;
  }
}
