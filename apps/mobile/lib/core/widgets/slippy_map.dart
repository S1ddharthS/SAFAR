import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../native/map_tiles.dart';
import '../theme/safar_theme.dart';

typedef MapLatLng = ({double lat, double lon});

class SlippyMapMarker {
  const SlippyMapMarker({
    required this.id,
    required this.lat,
    required this.lon,
    required this.label,
    this.isAnchor = false,
  });

  final String id;
  final double lat;
  final double lon;
  final String label;
  final bool isAnchor;

  MapLatLng get point => (lat: lat, lon: lon);
}

/// Web-Mercator slippy map with pan, pinch/double-tap zoom, tappable markers,
/// a radius ring and a route overlay.
///
/// Tiles come from a [MapTileProvider] supplied at build time; SAFAR ships no
/// tile endpoint. When a tile fails the widget keeps the pins and the route on
/// a neutral grid so the screen stays usable offline.
class SlippyMap extends StatefulWidget {
  const SlippyMap({
    super.key,
    required this.provider,
    required this.center,
    required this.markers,
    this.route = const [],
    this.radiusKm,
    this.selectedId,
    this.onMarkerTap,
    this.onMapTap,
    this.height = 320,
  });

  final MapTileProvider provider;

  /// The shared trip base (or the user's consented position for this screen).
  final MapLatLng center;
  final List<SlippyMapMarker> markers;
  final List<MapLatLng> route;
  final double? radiusKm;
  final String? selectedId;
  final ValueChanged<SlippyMapMarker>? onMarkerTap;
  final VoidCallback? onMapTap;
  final double height;

  @override
  State<SlippyMap> createState() => _SlippyMapState();
}

const double _tileSize = 256;

Offset _project(MapLatLng point, int zoom) {
  final world = _tileSize * (1 << zoom);
  final lat = point.lat.clamp(-85.05112878, 85.05112878);
  final sinLat = math.sin(lat * math.pi / 180);
  final x = (point.lon + 180) / 360 * world;
  final y =
      (0.5 -
          math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
      world;
  return Offset(x, y);
}

MapLatLng _unproject(Offset offset, int zoom) {
  final world = _tileSize * (1 << zoom);
  final lon = offset.dx / world * 360 - 180;
  final yNorm = offset.dy / world;
  final lat =
      (2 * math.atan(math.exp((0.5 - yNorm) * 2 * math.pi)) - math.pi / 2) *
      180 /
      math.pi;
  return (lat: lat.clamp(-85.05112878, 85.05112878), lon: _wrapLon(lon));
}

double _wrapLon(double lon) {
  var value = lon;
  while (value > 180) {
    value -= 360;
  }
  while (value < -180) {
    value += 360;
  }
  return value;
}

double _metersPerPixel(double lat, double zoom) =>
    156543.03392 * math.cos(lat.clamp(-85, 85) * math.pi / 180) /
    math.pow(2, zoom);

class _SlippyMapState extends State<SlippyMap> {
  double _zoom = 13;
  late MapLatLng _center = widget.center;
  bool _needsFit = true;
  Size _size = Size.zero;

  late MapLatLng _startCenter;
  late double _startZoom;
  late Offset _startFocal;

  final Set<String> _loadedTiles = <String>{};
  final Set<String> _failedTiles = <String>{};
  Set<String> _visibleTiles = <String>{};
  int _retryEpoch = 0;

  bool get _tilesLoading => _loadedTiles.isEmpty && _failedTiles.isEmpty;
  bool get _tilesOffline => _loadedTiles.isEmpty && _failedTiles.isNotEmpty;

  int get _minZoom => widget.provider.minZoom;
  int get _maxZoom => widget.provider.maxZoom;

  int _tileZoom(double zoom) =>
      zoom.floor().clamp(_minZoom, math.max(_minZoom, _maxZoom)).toInt();

  double _zoomScale(double zoom, int tileZoom) =>
      math.pow(2.0, zoom - tileZoom).toDouble();

  @override
  void didUpdateWidget(covariant SlippyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center != widget.center ||
        oldWidget.radiusKm != widget.radiusKm ||
        oldWidget.provider.urlTemplate != widget.provider.urlTemplate) {
      _needsFit = true;
      _center = widget.center;
      _loadedTiles.clear();
      _failedTiles.clear();
    }
  }

  void _pruneTiles(Set<String> visible) {
    _visibleTiles = visible;
    _loadedTiles.removeWhere((url) => !visible.contains(url));
    _failedTiles.removeWhere((url) => !visible.contains(url));
  }

  void _tileLoaded(String url) {
    if (!mounted) return;
    setState(() {
      _loadedTiles.add(url);
      _failedTiles.remove(url);
    });
  }

  void _tileFailed(String url) {
    if (!mounted || !_visibleTiles.contains(url)) return;
    setState(() {
      if (!_loadedTiles.contains(url)) _failedTiles.add(url);
    });
  }

  MapLatLng _geoAt(Offset local, Size size) {
    final tileZoom = _tileZoom(_zoom);
    final scale = _zoomScale(_zoom, tileZoom);
    final world =
        _project(_center, tileZoom) +
        (local - Offset(size.width / 2, size.height / 2)) / scale;
    return _unproject(world, tileZoom);
  }

  void _zoomAround(Offset local, double delta) {
    if (_size == Size.zero) return;
    final target = (_zoom + delta)
        .clamp(_minZoom.toDouble(), _maxZoom.toDouble())
        .toDouble();
    if (target == _zoom) return;
    final geo = _geoAt(local, _size);
    final tileZoom = _tileZoom(target);
    final scale = _zoomScale(target, tileZoom);
    final world = _project(geo, tileZoom);
    final centerWorld =
        world - (local - Offset(_size.width / 2, _size.height / 2)) / scale;
    setState(() {
      _zoom = target;
      _center = _unproject(centerWorld, tileZoom);
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startCenter = _center;
    _startZoom = _zoom;
    _startFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_size == Size.zero) return;
    final startTileZoom = _tileZoom(_startZoom);
    final startScale = _zoomScale(_startZoom, startTileZoom);
    final viewCenter = Offset(_size.width / 2, _size.height / 2);
    final focalGeo = _unproject(
      _project(_startCenter, startTileZoom) +
          (_startFocal - viewCenter) / startScale,
      startTileZoom,
    );

    final rawZoom =
        _startZoom + math.log(details.scale) / math.ln2;
    final zoom = rawZoom
        .clamp(_minZoom.toDouble(), _maxZoom.toDouble())
        .toDouble();
    final tileZoom = _tileZoom(zoom);
    final scale = _zoomScale(zoom, tileZoom);
    final centerWorld =
        _project(focalGeo, tileZoom) -
        (details.localFocalPoint - viewCenter) / scale;

    setState(() {
      _zoom = zoom;
      _center = _unproject(centerWorld, tileZoom);
    });
  }

  void _fitToContent(Size size) {
    var minLat = widget.center.lat;
    var maxLat = widget.center.lat;
    var minLon = widget.center.lon;
    var maxLon = widget.center.lon;

    void include(MapLatLng point) {
      minLat = math.min(minLat, point.lat);
      maxLat = math.max(maxLat, point.lat);
      minLon = math.min(minLon, point.lon);
      maxLon = math.max(maxLon, point.lon);
    }

    for (final marker in widget.markers) {
      include(marker.point);
    }
    for (final point in widget.route) {
      include(point);
    }
    final radius = widget.radiusKm;
    if (radius != null && radius > 0) {
      final dLat = radius / 111.32;
      final cosLat = math
          .cos(widget.center.lat * math.pi / 180)
          .abs()
          .clamp(0.1, 1.0);
      final dLon = radius / (111.32 * cosLat);
      minLat -= dLat;
      maxLat += dLat;
      minLon -= dLon;
      maxLon += dLon;
    }

    final northWest = _project((lat: maxLat, lon: minLon), 0);
    final southEast = _project((lat: minLat, lon: maxLon), 0);
    final width = (southEast.dx - northWest.dx).abs();
    final height = (southEast.dy - northWest.dy).abs();
    final availableWidth = math.max(size.width - 64, 32.0);
    final availableHeight = math.max(size.height - 96, 32.0);

    double zoom;
    if (width < 1e-9 && height < 1e-9) {
      zoom = 14;
    } else {
      final scaleX = width < 1e-9 ? double.infinity : availableWidth / width;
      final scaleY = height < 1e-9
          ? double.infinity
          : availableHeight / height;
      zoom = math.log(math.min(scaleX, scaleY)) / math.ln2;
    }
    final fitCeiling = math.min(_maxZoom, 16).toDouble();
    _zoom = zoom.clamp(_minZoom.toDouble(), fitCeiling).toDouble();
    _center = (
      lat: (minLat + maxLat) / 2,
      lon: _wrapLon((minLon + maxLon) / 2),
    );
  }

  void _retryTiles() {
    final urls = {
      ..._failedTiles,
      ..._visibleTileUrls(_size),
    };
    for (final url in urls) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(url));
    }
    setState(() {
      _loadedTiles.clear();
      _failedTiles.clear();
      _retryEpoch++;
    });
  }

  List<String> _visibleTileUrls(Size size) {
    if (size == Size.zero) return const [];
    final z = _tileZoom(_zoom);
    final scale = _zoomScale(_zoom, z);
    final n = 1 << z;
    final centerWorld = _project(_center, z);
    final left = centerWorld.dx - size.width / 2 / scale;
    final right = centerWorld.dx + size.width / 2 / scale;
    final top = centerWorld.dy - size.height / 2 / scale;
    final bottom = centerWorld.dy + size.height / 2 / scale;
    final urls = <String>[];
    final x0 = (left / _tileSize).floor();
    final x1 = (right / _tileSize).floor();
    final y0 = math.max(0, (top / _tileSize).floor());
    final y1 = math.min(n - 1, (bottom / _tileSize).floor());
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        urls.add(widget.provider.url(z, x % n, y));
      }
    }
    return urls;
  }

  bool _onScreen(Offset point, Size size) =>
      point.dx > -16 &&
      point.dx < size.width + 16 &&
      point.dy > -16 &&
      point.dy < size.height + 16;

  Offset? _offsetIfVisible(Offset? point, Size size) =>
      point != null && _onScreen(point, size) ? point : null;

  Widget _tileLayer(Size size, Color placeholder, Color gridColor) {
    final z = _tileZoom(_zoom);
    final scale = _zoomScale(_zoom, z);
    final n = 1 << z;
    final span = _tileSize * scale;
    final centerWorld = _project(_center, z);
    final viewCenter = Offset(size.width / 2, size.height / 2);

    final left = centerWorld.dx - size.width / 2 / scale;
    final right = centerWorld.dx + size.width / 2 / scale;
    final top = centerWorld.dy - size.height / 2 / scale;
    final bottom = centerWorld.dy + size.height / 2 / scale;

    final x0 = (left / _tileSize).floor();
    final x1 = (right / _tileSize).floor();
    final y0 = math.max(0, (top / _tileSize).floor());
    final y1 = math.min(n - 1, (bottom / _tileSize).floor());

    final tiles = <Widget>[];
    final visibleUrls = <String>{};
    var count = 0;
    for (var x = x0; x <= x1 && count < 160; x++) {
      for (var y = y0; y <= y1 && count < 160; y++) {
        count++;
        final wrapped = x % n;
        final url = widget.provider.url(z, wrapped, y);
        visibleUrls.add(url);
        final position =
            (Offset(x * _tileSize, y * _tileSize) - centerWorld) * scale +
            viewCenter;
        tiles.add(
          Positioned(
            left: position.dx,
            top: position.dy,
            width: span + 0.6,
            height: span + 0.6,
            child: _MapTileImage(
              key: ValueKey('$_retryEpoch/$z/$wrapped/$y'),
              url: url,
              background: placeholder,
              grid: gridColor,
              onLoaded: () => _tileLoaded(url),
              onFailed: () => _tileFailed(url),
            ),
          ),
        );
      }
    }
    _pruneTiles(visibleUrls);
    return Stack(children: tiles);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
            constraints.maxHeight.isFinite ? constraints.maxHeight : widget.height,
          );
          _size = size;
          if (_needsFit && size.width > 0 && size.height > 0) {
            _fitToContent(size);
            _needsFit = false;
          }

          final z = _tileZoom(_zoom);
          final scale = _zoomScale(_zoom, z);
          final centerWorld = _project(_center, z);
          final viewCenter = Offset(size.width / 2, size.height / 2);
          Offset project(MapLatLng point) =>
              (_project(point, z) - centerWorld) * scale + viewCenter;

          final anchorPosition = project(widget.center);
          final markerPositions = <String, Offset>{
            for (final marker in widget.markers)
              marker.id: project(marker.point),
          };
          final routePoints = [
            for (final point in widget.route) project(point),
          ];
          SlippyMapMarker? selected;
          for (final marker in widget.markers) {
            if (marker.id == widget.selectedId) {
              selected = marker;
              break;
            }
          }
          final radius = widget.radiusKm;
          final radiusPixels = radius == null || radius <= 0
              ? 0.0
              : radius *
                    1000 /
                    _metersPerPixel(_center.lat, _zoom);

          return Semantics(
            container: true,
            label:
                'Map of nearby places. Pinch to zoom, drag to pan, '
                'tap a pin to inspect the place.',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(color: palette.raised),
                  ),
                  Positioned.fill(
                    child: _tileLayer(size, palette.raised, palette.line),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _MapOverlayPainter(
                          anchor: anchorPosition,
                          route: routePoints,
                          radiusPixels: radiusPixels,
                          radiusLabel: radius == null || radius <= 0
                              ? null
                              : '${radius.toStringAsFixed(0)} km',
                          selectedLabel: selected?.label,
                          selectedOffset: selected == null
                              ? null
                              : _offsetIfVisible(
                                  markerPositions[selected.id],
                                  size,
                                ),
                          showAnchorLabel: _onScreen(anchorPosition, size),
                          routeColor: palette.ember,
                          ringColor: palette.jade,
                          ringFill: palette.jade.withValues(alpha: 0.06),
                          labelColor: palette.ink,
                          labelBackground: palette.surface.withValues(
                            alpha: 0.92,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onDoubleTapDown: (details) =>
                          _zoomAround(details.localPosition, 1),
                      onTap: () => widget.onMapTap?.call(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  for (final marker in widget.markers)
                    if (markerPositions[marker.id] case final Offset position
                        when marker.isAnchor)
                      Positioned(
                        left: position.dx - 9,
                        top: position.dy - 9,
                        width: 18,
                        height: 18,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: palette.ember,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: palette.surface,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: palette.shadow.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (markerPositions[marker.id]
                        case final Offset position)
                      Positioned(
                        left: position.dx - 22,
                        top: position.dy - 42,
                        width: 44,
                        height: 46,
                        child: _MarkerPin(
                          marker: marker,
                          selected: marker.id == widget.selectedId,
                          palette: palette,
                          onTap: () => widget.onMarkerTap?.call(marker),
                        ),
                      ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _TileStatusChip(
                      loading: _tilesLoading,
                      offline: _tilesOffline,
                      onRetry: _retryTiles,
                      palette: palette,
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 12,
                    child: _MapControls(
                      palette: palette,
                      onZoomIn: () =>
                          _zoomAround(Offset(size.width / 2, size.height / 2), 1),
                      onZoomOut: () =>
                          _zoomAround(Offset(size.width / 2, size.height / 2), -1),
                      onFit: () {
                        setState(() => _needsFit = true);
                      },
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    right: 64,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.provider.attribution,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.labelSmall?.copyWith(
                            fontSize: 9,
                            color: palette.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MapTileImage extends StatefulWidget {
  const _MapTileImage({
    super.key,
    required this.url,
    required this.background,
    required this.grid,
    required this.onLoaded,
    required this.onFailed,
  });

  final String url;
  final Color background;
  final Color grid;
  final VoidCallback onLoaded;
  final VoidCallback onFailed;

  @override
  State<_MapTileImage> createState() => _MapTileImageState();
}

class _MapTileImageState extends State<_MapTileImage> {
  bool _reported = false;

  void _report(bool ok) {
    if (_reported) return;
    _reported = true;
    scheduleMicrotask(() {
      if (!mounted) return;
      if (ok) {
        widget.onLoaded();
      } else {
        widget.onFailed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: widget.background,
      child: CustomPaint(painter: _TileGridPainter(widget.grid)),
    );
    return Image.network(
      widget.url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) _report(true);
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
      errorBuilder: (context, error, stackTrace) {
        _report(false);
        return placeholder;
      },
    );
  }
}

class _TileGridPainter extends CustomPainter {
  const _TileGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    const step = 32.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TileGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _MarkerPin extends StatelessWidget {
  const _MarkerPin({
    required this.marker,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final SlippyMapMarker marker;
  final bool selected;
  final SafarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: marker.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Icon(
            Icons.location_on_rounded,
            size: selected ? 34 : 28,
            color: selected ? palette.ink : palette.jade,
            shadows: [
              Shadow(
                color: palette.shadow.withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapOverlayPainter extends CustomPainter {
  const _MapOverlayPainter({
    required this.anchor,
    required this.route,
    required this.radiusPixels,
    required this.radiusLabel,
    required this.selectedLabel,
    required this.selectedOffset,
    required this.showAnchorLabel,
    required this.routeColor,
    required this.ringColor,
    required this.ringFill,
    required this.labelColor,
    required this.labelBackground,
  });

  final Offset anchor;
  final List<Offset> route;
  final double radiusPixels;
  final String? radiusLabel;
  final String? selectedLabel;
  final Offset? selectedOffset;
  final bool showAnchorLabel;
  final Color routeColor;
  final Color ringColor;
  final Color ringFill;
  final Color labelColor;
  final Color labelBackground;

  @override
  void paint(Canvas canvas, Size size) {
    if (radiusPixels > 0) {
      canvas.drawCircle(anchor, radiusPixels, Paint()..color = ringFill);
      canvas.drawCircle(
        anchor,
        radiusPixels,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = ringColor.withValues(alpha: 0.65),
      );
      if (radiusLabel != null) {
        _paintLabel(
          canvas,
          radiusLabel!,
          Offset(anchor.dx + 4, anchor.dy - radiusPixels - 16),
          size,
        );
      }
    }

    if (route.length > 1) {
      final path = Path();
      for (var i = 0; i < route.length; i++) {
        if (i == 0) {
          path.moveTo(route[i].dx, route[i].dy);
        } else {
          path.lineTo(route[i].dx, route[i].dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = routeColor.withValues(alpha: 0.8),
      );
      final dot = Paint()..color = routeColor;
      for (final point in route) {
        canvas.drawCircle(point, 2.8, dot);
      }
    }

    if (showAnchorLabel) {
      _paintLabel(
        canvas,
        'Trip base',
        Offset(anchor.dx + 8, anchor.dy + 2),
        size,
      );
    }

    final offset = selectedOffset;
    final label = selectedLabel;
    if (offset != null && label != null) {
      _paintLabel(canvas, label, Offset(offset.dx, offset.dy + 8), size);
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset at, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          height: 1.2,
          color: labelColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(size.width - 24, 24));
    final left = (at.dx - painter.width / 2)
        .clamp(6.0, math.max(6.0, size.width - painter.width - 6))
        .toDouble();
    final top = at.dy
        .clamp(4.0, math.max(4.0, size.height - painter.height - 8))
        .toDouble();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        left - 4,
        top - 2,
        painter.width + 8,
        painter.height + 4,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, Paint()..color = labelBackground);
    painter.paint(canvas, Offset(left, top));
  }

  @override
  bool shouldRepaint(covariant _MapOverlayPainter oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.route != route ||
      oldDelegate.radiusPixels != radiusPixels ||
      oldDelegate.radiusLabel != radiusLabel ||
      oldDelegate.selectedLabel != selectedLabel ||
      oldDelegate.selectedOffset != selectedOffset ||
      oldDelegate.showAnchorLabel != showAnchorLabel ||
      oldDelegate.routeColor != routeColor ||
      oldDelegate.ringColor != ringColor;
}

class _TileStatusChip extends StatelessWidget {
  const _TileStatusChip({
    required this.loading,
    required this.offline,
    required this.onRetry,
    required this.palette,
  });

  final bool loading;
  final bool offline;
  final VoidCallback onRetry;
  final SafarPalette palette;

  @override
  Widget build(BuildContext context) {
    if (!loading && !offline) return const SizedBox.shrink();
    final label = loading
        ? 'Loading map…'
        : 'Map tiles offline · pins still work';
    return Material(
      color: palette.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: offline ? onRetry : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              else
                Icon(
                  Icons.cloud_off_rounded,
                  size: 13,
                  color: palette.muted,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.texts.labelSmall?.copyWith(
                  fontSize: 10,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.palette,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final SafarPalette palette;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  Widget _button(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.surface.withValues(alpha: 0.94),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: palette.ink),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.add_rounded, 'Zoom in', onZoomIn),
        const SizedBox(height: 6),
        _button(Icons.remove_rounded, 'Zoom out', onZoomOut),
        const SizedBox(height: 6),
        _button(Icons.center_focus_strong_rounded, 'Fit places', onFit),
      ],
    );
  }
}
