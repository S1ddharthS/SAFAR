import 'package:flutter/foundation.dart';

/// A slippy-map tile source supplied at build time.
///
/// SAFAR never bundles a tile endpoint and never assumes a provider's free
/// tier is acceptable for this app. Supply a licensed endpoint (MapTiler,
/// Mapbox Static Tiles, Thunderforest, an in-house tile server, ...) with
/// `--dart-define=SAFAR_MAP_TILE_URL=...` and its required attribution with
/// `SAFAR_MAP_TILE_ATTRIBUTION`. The template must contain `{z}`, `{x}` and
/// `{y}`; `{s}` is optional and rotates through `SAFAR_MAP_TILE_SUBDOMAINS`.
@immutable
class MapTileProvider {
  const MapTileProvider({
    required this.urlTemplate,
    required this.attribution,
    required this.minZoom,
    required this.maxZoom,
    this.subdomains = const [],
  });

  final String urlTemplate;
  final String attribution;
  final int minZoom;
  final int maxZoom;
  final List<String> subdomains;

  String url(int z, int x, int y) {
    var out = urlTemplate
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
    if (subdomains.isNotEmpty) {
      out = out.replaceAll('{s}', subdomains[(x + y) % subdomains.length]);
    }
    return out;
  }
}

/// Result of reading the tile settings from the compile-time environment.
class MapTileConfig {
  const MapTileConfig({this.provider, this.note});

  final MapTileProvider? provider;

  /// Human-readable reason the tile layer is off, shown in the UI.
  final String? note;

  bool get hasTiles => provider != null;

  static const String _templateKey = 'SAFAR_MAP_TILE_URL';

  static MapTileConfig fromEnvironment() {
    const template = String.fromEnvironment(_templateKey);
    const attribution = String.fromEnvironment('SAFAR_MAP_TILE_ATTRIBUTION');
    const subdomainsRaw = String.fromEnvironment('SAFAR_MAP_TILE_SUBDOMAINS');
    const minZoomRaw = String.fromEnvironment(
      'SAFAR_MAP_TILE_MIN_ZOOM',
      defaultValue: '2',
    );
    const maxZoomRaw = String.fromEnvironment(
      'SAFAR_MAP_TILE_MAX_ZOOM',
      defaultValue: '18',
    );

    final trimmed = template.trim();
    if (trimmed.isEmpty) {
      return const MapTileConfig(
        note:
            'Schematic map. Tile provider not configured for this build '
            '(SAFAR_MAP_TILE_URL).',
      );
    }
    if (!trimmed.contains('{z}') ||
        !trimmed.contains('{x}') ||
        !trimmed.contains('{y}')) {
      return const MapTileConfig(
        note:
            'Schematic map. SAFAR_MAP_TILE_URL must contain {z}, {x} and {y} '
            'placeholders.',
      );
    }

    final probe = trimmed
        .replaceAll('{z}', '0')
        .replaceAll('{x}', '0')
        .replaceAll('{y}', '0')
        .replaceAll('{s}', 'a');
    final uri = Uri.tryParse(probe);
    if (uri == null || uri.host.isEmpty) {
      return const MapTileConfig(
        note: 'Schematic map. SAFAR_MAP_TILE_URL is not a valid absolute URL.',
      );
    }
    if (uri.scheme != 'https' && !(kDebugMode && uri.scheme == 'http')) {
      return const MapTileConfig(
        note:
            'Schematic map. Tile endpoints must use HTTPS in release builds; '
            'plain HTTP is only accepted in debug builds.',
      );
    }

    final minZoom = int.tryParse(minZoomRaw.trim()) ?? 2;
    final maxZoom = int.tryParse(maxZoomRaw.trim()) ?? 18;
    final lower = minZoom.clamp(1, 22);
    final upper = maxZoom.clamp(lower, 22);
    final subdomains = subdomainsRaw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final attributionText = attribution.trim().isEmpty
        ? 'Map tiles © ${uri.host}'
        : attribution.trim();

    return MapTileConfig(
      provider: MapTileProvider(
        urlTemplate: trimmed,
        attribution: attributionText,
        minZoom: lower,
        maxZoom: upper,
        subdomains: subdomains,
      ),
    );
  }
}
