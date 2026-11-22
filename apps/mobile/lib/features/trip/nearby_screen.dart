import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/discovery.dart';
import '../../core/models/itinerary.dart';
import '../../core/native/map_tiles.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../../core/widgets/slippy_map.dart';

const _categories = [
  'museum',
  'park',
  'market',
  'viewpoint',
  'restaurant',
  'landmark',
];

typedef _RoutePoint = ({double lat, double lon, String title});

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  double _radiusKm = 5;
  String? _category;
  NearbyItem? _selected;
  double? _originLat;
  double? _originLon;
  bool _locating = false;
  late final MapTileConfig _tiles = MapTileConfig.fromEnvironment();

  NearbyQuery _query() => NearbyQuery(
    tripId: widget.tripId,
    lat: _originLat,
    lon: _originLon,
    radiusKm: _radiusKm,
    category: _category,
  );

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;
    if (_originLat != null) {
      setState(() {
        _originLat = null;
        _originLon = null;
        _selected = null;
      });
      _notify('Back to the shared trip base.');
      return;
    }
    final bool sharing;
    try {
      sharing = (await ref.read(meProvider.future)).profile.locationSharing;
    } on Object {
      _notify('Could not confirm your location privacy setting. Try again.');
      return;
    }
    if (!sharing) {
      _notify(
        'Precise location is off. Enable it in Settings → Privacy before '
        'using your position.',
      );
      return;
    }
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _notify('Location services are off on this device.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _notify('Location stays off. The shared trip base still works.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _originLat = position.latitude;
        _originLon = position.longitude;
        _selected = null;
      });
      _notify(
        'Distances now use your current position for this screen only. '
        'It is not shared with the group.',
      );
    } on Object {
      _notify('Could not read your location. You can keep using the trip base.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nearby = ref.watch(nearbyProvider(_query()));
    final itinerary = ref.watch(itineraryProvider(widget.tripId)).valueOrNull;
    final route = _routePoints(itinerary);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map & nearby'),
        actions: [
          IconButton(
            tooltip: _originLat == null
                ? 'Use my current location'
                : 'Back to shared trip base',
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _originLat == null
                        ? Icons.my_location_rounded
                        : Icons.location_on_rounded,
                  ),
          ),
        ],
      ),
      body: AsyncView<NearbyResponse>(
        value: nearby,
        onRetry: () => ref.invalidate(nearbyProvider(_query())),
        skeleton: const SkeletonList(count: 3, itemHeight: 84),
        builder: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          children: [
            if (_tiles.provider case final provider?)
              SlippyMap(
                key: ValueKey('map-${provider.urlTemplate}'),
                provider: provider,
                center: (
                  lat: _originLat ?? data.base.lat,
                  lon: _originLon ?? data.base.lon,
                ),
                markers: _markers(data),
                route: [
                  for (final point in route)
                    (lat: point.lat, lon: point.lon),
                ],
                radiusKm: data.radiusKm,
                selectedId: _selected?.activity.id,
                onMarkerTap: (marker) => _selectMarker(data.items, marker),
                onMapTap: () => setState(() => _selected = null),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  color: context.safar.raised,
                  child: _RelativeMap(
                    base: data.base,
                    radiusKm: data.radiusKm,
                    items: data.items,
                    route: route,
                    selectedId: _selected?.activity.id,
                    onSelect: (item) => setState(() => _selected = item),
                  ),
                ),
              ),
            if (_tiles.provider == null && _tiles.note != null) ...[
              const SizedBox(height: 6),
              Text(_tiles.note!, style: context.texts.labelSmall),
            ],
            const SizedBox(height: 8),
            if (_selected != null)
              SafarCard(
                onTap: () => context.push(
                  '/trips/${widget.tripId}/places/${_selected!.activity.id}',
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selected!.activity.name,
                            style: context.texts.titleSmall,
                          ),
                          Text(
                            '${_selected!.distanceKm.toStringAsFixed(1)} km · '
                            '~${_selected!.travelMinutes} min · '
                            '${titleCase(_selected!.activity.place?.category ?? 'place')}',
                            style: context.texts.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: context.safar.faint),
                  ],
                ),
              )
            else
              Text(_mapHint(data.radiusKm), style: context.texts.labelSmall),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final radius in const [2.0, 5.0, 10.0, 20.0, 35.0])
                  ChoiceChip(
                    label: Text('${radius.toStringAsFixed(0)} km'),
                    selected: _radiusKm == radius,
                    onSelected: (_) => setState(() {
                      _radiusKm = radius;
                      _selected = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _category == null,
                  onSelected: (_) => setState(() {
                    _category = null;
                    _selected = null;
                  }),
                ),
                for (final category in _categories)
                  ChoiceChip(
                    label: Text(titleCase(category)),
                    selected: _category == category,
                    onSelected: (_) => setState(() {
                      _category = category;
                      _selected = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SectionHeader(
              eyebrow: 'Within ${data.radiusKm.toStringAsFixed(0)} km',
              title: data.items.isEmpty
                  ? 'Nothing found nearby'
                  : '${data.items.length} catalog places',
            ),
            if (data.items.isEmpty)
              const SafarEmpty(
                icon: Icons.travel_explore,
                title: 'No catalog places here',
                message: 'Widen the radius or clear the category filter.',
              )
            else
              for (final item in data.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SafarCard(
                    onTap: () => setState(() => _selected = item),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: context.safar.jadeSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.place_outlined,
                            size: 18,
                            color: context.safar.jade,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.activity.name,
                                style: context.texts.titleSmall,
                              ),
                              Text(
                                '${item.distanceKm.toStringAsFixed(1)} km · '
                                '~${item.travelMinutes} min · '
                                '${titleCase(item.activity.place?.category ?? 'place')}',
                                style: context.texts.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Open place',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => context.push(
                            '/trips/${widget.tripId}/places/${item.activity.id}',
                          ),
                          icon: Icon(
                            Icons.open_in_new,
                            size: 17,
                            color: context.safar.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (route.length > 1) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 18,
                    height: 2,
                    color: context.safar.ember,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Confirmed route order (${route.length} stops)',
                    style: context.texts.labelSmall,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            SourceLabel(source: data.disclosure),
          ],
        ),
      ),
    );
  }

  String _mapHint(double radiusKm) {
    final base = _originLat == null
        ? 'The ring marks the ${radiusKm.toStringAsFixed(0)} km search radius '
              'around the shared trip base — never a live member location.'
        : 'Distances use your current position for this screen only — it is '
              'not shared with the group.';
    return _tiles.hasTiles
        ? 'Tap a pin to inspect a place. Pinch or double-tap to zoom, drag to '
              'pan. $base'
        : 'Tap a dot to inspect a place. $base';
  }

  List<SlippyMapMarker> _markers(NearbyResponse data) {
    final markers = <SlippyMapMarker>[
      SlippyMapMarker(
        id: '__base',
        lat: data.base.lat,
        lon: data.base.lon,
        label: 'Shared trip base',
        isAnchor: true,
      ),
    ];
    for (final item in data.items) {
      final place = item.activity.place;
      if (place == null) continue;
      markers.add(
        SlippyMapMarker(
          id: item.activity.id,
          lat: place.lat,
          lon: place.lon,
          label: item.activity.name,
        ),
      );
    }
    return markers;
  }

  void _selectMarker(List<NearbyItem> items, SlippyMapMarker marker) {
    if (marker.isAnchor) return;
    for (final item in items) {
      if (item.activity.id == marker.id) {
        setState(() => _selected = item);
        return;
      }
    }
  }

  List<_RoutePoint> _routePoints(Itinerary? itinerary) {
    if (itinerary == null) return const [];
    final items = itinerary.items
        .where((item) => !item.cancelled && item.activity?.place != null)
        .toList()
      ..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        return byDay != 0 ? byDay : a.startTime.compareTo(b.startTime);
      });
    return [
      for (final item in items)
        (
          lat: item.activity!.place!.lat,
          lon: item.activity!.place!.lon,
          title: item.title,
        ),
    ];
  }
}

class _RelativeMap extends StatelessWidget {
  const _RelativeMap({
    required this.base,
    required this.radiusKm,
    required this.items,
    required this.route,
    required this.selectedId,
    required this.onSelect,
  });

  final NearbyBase base;
  final double radiusKm;
  final List<NearbyItem> items;
  final List<_RoutePoint> route;
  final String? selectedId;
  final ValueChanged<NearbyItem> onSelect;

  double get _maxKm {
    var maxKm = radiusKm;
    for (final point in route) {
      final extent = _kmOffset(base, point.lat, point.lon);
      maxKm = math.max(maxKm, math.max(extent.dx.abs(), extent.dy.abs()));
    }
    return maxKm <= 0 ? 1 : maxKm;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SizedBox(
      height: 250,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final maxKm = _maxKm;
          return GestureDetector(
            onTapUp: (details) {
              NearbyItem? best;
              var bestDistance = 22.0;
              for (final item in items) {
                final place = item.activity.place;
                if (place == null) continue;
                final offset = _project(base, place.lat, place.lon, size, maxKm);
                final distance = (offset - details.localPosition).distance;
                if (distance < bestDistance) {
                  best = item;
                  bestDistance = distance;
                }
              }
              if (best != null) onSelect(best);
            },
            child: CustomPaint(
              size: size,
              painter: _MapPainter(
                base: base,
                radiusKm: radiusKm,
                maxKm: maxKm,
                items: items,
                route: route,
                selectedId: selectedId,
                background: palette.raised,
                ring: palette.line,
                ink: palette.ink,
                muted: palette.muted,
                jade: palette.jade,
                ember: palette.ember,
                surface: palette.surface,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Straight-line kilometre offsets from the base, east (dx) and north (dy).
Offset _kmOffset(NearbyBase base, double lat, double lon) {
  final latKm = (lat - base.lat) * 111.32;
  final lonKm =
      (lon - base.lon) * 111.32 * math.cos(base.lat * math.pi / 180).abs();
  return Offset(lonKm, latKm);
}

Offset _project(NearbyBase base, double lat, double lon, Size size, double maxKm) {
  final offset = _kmOffset(base, lat, lon);
  final half = size.shortestSide / 2 - 20;
  final scale = half / maxKm;
  return Offset(
    size.width / 2 + offset.dx * scale,
    size.height / 2 - offset.dy * scale,
  );
}

class _MapPainter extends CustomPainter {
  const _MapPainter({
    required this.base,
    required this.radiusKm,
    required this.maxKm,
    required this.items,
    required this.route,
    required this.selectedId,
    required this.background,
    required this.ring,
    required this.ink,
    required this.muted,
    required this.jade,
    required this.ember,
    required this.surface,
  });

  final NearbyBase base;
  final double radiusKm;
  final double maxKm;
  final List<NearbyItem> items;
  final List<_RoutePoint> route;
  final String? selectedId;
  final Color background;
  final Color ring;
  final Color ink;
  final Color muted;
  final Color jade;
  final Color ember;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final half = size.shortestSide / 2 - 20;
    final scale = half / maxKm;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    canvas.drawCircle(center, radiusKm * scale, ringPaint);

    final ringLabel = TextPainter(
      text: TextSpan(
        text: '${radiusKm.toStringAsFixed(0)} km',
        style: TextStyle(fontSize: 10, color: muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ringLabel.paint(
      canvas,
      Offset(center.dx + 4, center.dy - radiusKm * scale - 14),
    );

    if (route.length > 1) {
      final path = Path();
      for (var i = 0; i < route.length; i++) {
        final point = _project(base, route[i].lat, route[i].lon, size, maxKm);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = ember.withValues(alpha: 0.55),
      );
      final routeDot = Paint()..color = ember;
      for (final stop in route) {
        canvas.drawCircle(
          _project(base, stop.lat, stop.lon, size, maxKm),
          2.6,
          routeDot,
        );
      }
    }

    final basePaint = Paint()..color = ember;
    canvas.drawCircle(center, 4, basePaint);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ember.withValues(alpha: 0.5),
    );

    String? selectedName;
    Offset? selectedOffset;
    final dotPaint = Paint()..color = jade;
    for (final item in items) {
      final place = item.activity.place;
      if (place == null) continue;
      final offset = _project(base, place.lat, place.lon, size, maxKm);
      if (item.activity.id == selectedId) {
        selectedName = item.activity.name;
        selectedOffset = offset;
        canvas.drawCircle(offset, 8, Paint()..color = surface);
        canvas.drawCircle(
          offset,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = ink,
        );
      }
      canvas.drawCircle(offset, 3.4, dotPaint);
    }

    if (selectedName != null && selectedOffset != null) {
      final label = TextPainter(
        text: TextSpan(
          text: selectedName,
          style: TextStyle(fontSize: 11, color: ink, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width - 24);
      final dx = (selectedOffset.dx - label.width / 2)
          .clamp(8.0, size.width - label.width - 8);
      final dy = (selectedOffset.dy + 12).clamp(8.0, size.height - 20);
      label.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.selectedId != selectedId ||
      oldDelegate.radiusKm != radiusKm ||
      oldDelegate.items != items ||
      oldDelegate.route != route;
}
