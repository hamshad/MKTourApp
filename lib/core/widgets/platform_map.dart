import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'map_marker_icons.dart';

class MapMarker {
  final String id;
  final double lat;
  final double lng;
  final Widget? child; // Not used in Google Maps but kept for API compatibility
  final String? title;
  final Color? markerColor; // Used for custom marker colors

  MapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    this.child,
    this.title,
    this.markerColor,
  });

  /// Convert Color to Google Maps marker hue
  double? get markerHue {
    if (markerColor == null) return null;
    
    // Convert common colors to Google Maps hue values
    if (markerColor == Colors.green || markerColor!.value == Colors.green.value) {
      return BitmapDescriptor.hueGreen;
    } else if (markerColor == Colors.red || markerColor!.value == Colors.red.value) {
      return BitmapDescriptor.hueRed;
    } else if (markerColor == Colors.blue || markerColor!.value == Colors.blue.value) {
      return BitmapDescriptor.hueBlue;
    } else if (markerColor == Colors.orange || markerColor!.value == Colors.orange.value) {
      return BitmapDescriptor.hueOrange;
    } else if (markerColor == Colors.yellow || markerColor!.value == Colors.yellow.value) {
      return BitmapDescriptor.hueYellow;
    } else if (markerColor == Colors.cyan || markerColor!.value == Colors.cyan.value) {
      return BitmapDescriptor.hueCyan;
    } else if (markerColor == Colors.purple || markerColor!.value == Colors.purple.value) {
      return BitmapDescriptor.hueViolet;
    }
    
    // Default: try to extract hue from the color
    final hslColor = HSLColor.fromColor(markerColor!);
    return hslColor.hue;
  }
}

class MapPolyline {
  final String id;
  final List<latlong.LatLng> points;
  final Color color;
  final double width;

  MapPolyline({
    required this.id,
    required this.points,
    required this.color,
    required this.width,
  });
}

class PlatformMap extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final Function(double lat, double lng)? onTap;
  final List<MapMarker> markers;
  final List<MapPolyline> polylines;
  final dynamic bounds; // Kept for API compatibility
  final double bearing;
  final double tilt;
  final bool interactive;

  /// Show Google's native my-location dot + recenter button.
  /// Defaults to false because our own position markers (user/driver/pickup)
  /// already mark the device location — leaving it on draws TWO pins on the
  /// same spot at slightly different sizes. Opt in only on maps with no
  /// custom position marker (e.g. the home tab).
  final bool showMyLocationDot;

  const PlatformMap({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.onTap,
    this.markers = const [],
    this.polylines = const [],
    this.bounds,
    this.bearing = 0.0,
    this.tilt = 0.0,
    this.interactive = true,
    this.showMyLocationDot = false,
  });

  @override
  State<PlatformMap> createState() => _PlatformMapState();
}

class _PlatformMapState extends State<PlatformMap> {
  GoogleMapController? _controller;

  /// Custom bitmap icons per marker key (`id + color + zoom bucket`). Filled
  /// in asynchronously; markers fall back to distinct hues until ready so
  /// pins are never all the same red.
  final Map<String, BitmapDescriptor> _icons = {};

  /// Current zoom bucket — pins shrink when zoomed out, grow when zoomed in.
  String _zoomBucket = 'mid';

  @override
  void initState() {
    super.initState();
    _ensureIcons();
  }

  @override
  void didUpdateWidget(PlatformMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_markerKeys(widget.markers).join() !=
        _markerKeys(oldWidget.markers).join()) {
      _ensureIcons();
    }
    
    // Animate to new location if coordinates changed
    if (widget.initialLat != oldWidget.initialLat || widget.initialLng != oldWidget.initialLng) {
      _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(widget.initialLat, widget.initialLng),
            zoom: 16.0,
            bearing: widget.bearing,
            tilt: widget.tilt,
          ),
        ),
      );
    }
    
    if (widget.bounds != null && widget.bounds != oldWidget.bounds) {
      _fitBounds();
    }
  }

  /// Update camera position for navigation (can be called externally if needed)
  Future<void> updateCamera({
    required double lat,
    required double lng,
    double? bearing,
    double? tilt,
    double? zoom,
  }) async {
    if (_controller == null) return;
    
    await _controller!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(lat, lng),
          zoom: zoom ?? 16.0,
          bearing: bearing ?? 0.0,
          tilt: tilt ?? 0.0,
        ),
      ),
    );
  }
  void _fitBounds() {
    if (_controller == null || widget.bounds == null) {
      debugPrint('🗺️ PlatformMap: Cannot fit bounds - controller: ${_controller != null}, bounds: ${widget.bounds != null}');
      return;
    }

    try {
      // Extract SW/NE from either google_maps_flutter or flutter_map LatLngBounds
      double? swLat, swLng, neLat, neLng;
      try {
        final sw = widget.bounds.southwest;
        final ne = widget.bounds.northeast;
        swLat = sw.latitude; swLng = sw.longitude;
        neLat = ne.latitude; neLng = ne.longitude;
      } catch (_) {
        final sw = widget.bounds.southWest;
        final ne = widget.bounds.northEast;
        swLat = sw.latitude; swLng = sw.longitude;
        neLat = ne.latitude; neLng = ne.longitude;
      }

      if (swLat == null || swLng == null || neLat == null || neLng == null) return;

      debugPrint('🗺️ PlatformMap: Fitting bounds...');
      debugPrint('   → SW: ($swLat, $swLng)');
      debugPrint('   → NE: ($neLat, $neLng)');

      final googleBounds = LatLngBounds(
        southwest: LatLng(swLat, swLng),
        northeast: LatLng(neLat, neLng),
      );

      // Use moveCamera instead of animateCamera for more reliable initial positioning
      _controller!.moveCamera(
        CameraUpdate.newLatLngBounds(googleBounds, 40), // Smaller padding for 180px height map
      );
      debugPrint('🗺️ PlatformMap: Bounds fitted successfully');
    } catch (e) {
      debugPrint('🗺️ PlatformMap: Error fitting bounds: $e');
      // Fallback: try to at least center on the first marker
      if (widget.markers.isNotEmpty) {
        final m = widget.markers.first;
        _controller?.moveCamera(
          CameraUpdate.newLatLngZoom(LatLng(m.lat, m.lng), 14),
        );
      }
    }
  }

  String _markerKey(MapMarker m) =>
      '${m.id}_${m.markerColor?.value ?? 0}_$_zoomBucket';

  static List<String> _markerKeys(List<MapMarker> markers) =>
      markers.map((m) => '${m.id}_${m.markerColor?.value ?? 0}').toList();

  void _onCameraMove(CameraPosition position) {
    final bucket = MapMarkerIcons.bucket(position.zoom);
    if (bucket != _zoomBucket) {
      setState(() => _zoomBucket = bucket);
      _ensureIcons();
    }
  }

  /// Resolve custom bitmap icons for markers that have one (pickup, dropoff,
  /// numbered stops, driver car, user dot). One rebuild when all are ready.
  Future<void> _ensureIcons() async {
    final pending = <String, Future<BitmapDescriptor>>{};
    for (final m in widget.markers) {
      final key = _markerKey(m);
      if (_icons.containsKey(key)) continue;
      final future = _iconFor(m);
      if (future != null) pending[key] = future;
    }
    if (pending.isEmpty) return;
    try {
      final resolved = await Future.wait(pending.values);
      if (!mounted) return;
      setState(() {
        var i = 0;
        for (final key in pending.keys) {
          _icons[key] = resolved[i++];
        }
      });
    } catch (e) {
      debugPrint('🗺️ PlatformMap: custom icon failed: $e');
    }
  }

  /// Custom icon per marker id, sized for the current zoom bucket. Stops
  /// (`stop_N`) render their number with the status tint carried in
  /// [MapMarker.markerColor]; null = default hue pin.
  Future<BitmapDescriptor>? _iconFor(MapMarker m) {
    final scale = MapMarkerIcons.bucketScale(_zoomBucket);
    final id = m.id.toLowerCase();
    if (id == 'pickup') return MapMarkerIcons.pickup(scale: scale);
    if (id == 'dropoff' || id == 'destination') {
      return MapMarkerIcons.dropoff(scale: scale);
    }
    if (id.startsWith('stop')) {
      final n =
          int.tryParse(id.split('_').last) ?? int.tryParse(m.title ?? '') ?? 1;
      final bg = m.markerColor ?? Colors.white;
      final fg = bg == Colors.white ? Colors.black : Colors.white;
      return MapMarkerIcons.stop(number: n, bg: bg, fg: fg, scale: scale);
    }
    if (id == 'driver') return MapMarkerIcons.driver(scale: scale);
    if (id == 'user') return MapMarkerIcons.userDot(scale: scale);
    return null;
  }

  /// Instant hue fallback (before bitmaps load) — distinct per role so pins
  /// are never uniform red: green pickup, red dropoff, orange stops,
  /// azure car, blue user dot.
  static double? _fallbackHue(MapMarker m) {
    final id = m.id.toLowerCase();
    // Stops: keep the status tint (green/blue) while bitmaps generate;
    // pending (white) falls back to orange so it never reads as red.
    if (id.startsWith('stop')) {
      if (m.markerColor == null || m.markerColor == Colors.white) {
        return BitmapDescriptor.hueOrange;
      }
      return m.markerHue;
    }
    if (m.markerHue != null) return m.markerHue;
    if (id == 'pickup') return BitmapDescriptor.hueGreen;
    if (id == 'dropoff' || id == 'destination') {
      return BitmapDescriptor.hueRed;
    }
    if (id == 'driver') return BitmapDescriptor.hueAzure;
    if (id == 'user') return BitmapDescriptor.hueBlue;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Debug logging removed to prevent log spam

    // Convert MapMarker to Google Maps Marker (Moved to build for reactivity)
    final googleMarkers = widget.markers.map((m) {
      final custom = _icons[_markerKey(m)];
      final hue = _fallbackHue(m);
      return Marker(
        markerId: MarkerId(m.id),
        position: LatLng(m.lat, m.lng),
        infoWindow: InfoWindow(title: m.title ?? m.id),
        icon: custom ??
            (hue != null
                ? BitmapDescriptor.defaultMarkerWithHue(hue)
                : BitmapDescriptor.defaultMarker),
      );
    }).toSet();

    // Convert MapPolyline to Google Maps Polyline (Moved to build for reactivity)
    final googlePolylines = widget.polylines.map((p) {
      return Polyline(
        polylineId: PolylineId(p.id),
        points: p.points
            .map((pt) => LatLng(pt.latitude, pt.longitude))
            .toList(),
        color: p.color,
        width: 6, // Increased width for better visibility
        geodesic: true,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 1, // Ensure it's above the map tiles
      );
    }).toSet();

    // Determine initial camera target: prefer center of bounds, fallback to initialLat/Lng
    LatLng initialTarget = LatLng(widget.initialLat, widget.initialLng);
    if (widget.bounds != null) {
      try {
        // Works with both google_maps_flutter and flutter_map LatLngBounds
        final sw = widget.bounds.southwest;
        final ne = widget.bounds.northeast;
        initialTarget = LatLng(
          (sw.latitude + ne.latitude) / 2,
          (sw.longitude + ne.longitude) / 2,
        );
      } catch (_) {
        try {
          // flutter_map uses southWest/northEast (camelCase)
          final sw = widget.bounds.southWest;
          final ne = widget.bounds.northEast;
          initialTarget = LatLng(
            (sw.latitude + ne.latitude) / 2,
            (sw.longitude + ne.longitude) / 2,
          );
        } catch (_) {
          // Keep fallback
        }
      }
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: widget.bounds != null ? 12.0 : 14.0, // Zoom out slightly if showing bounds
        bearing: widget.bearing,
        tilt: widget.tilt,
      ),
      markers: googleMarkers,
      polylines: googlePolylines,
      onCameraMove: _onCameraMove,
      onMapCreated: (GoogleMapController controller) {
        debugPrint('🗺️ PlatformMap: Google Map created successfully');
        _controller = controller;
        if (widget.bounds != null) {
          // Extra delay to ensure layout is complete
          Future.delayed(const Duration(milliseconds: 600), _fitBounds);
        }
      },
      onTap: (LatLng position) {
        widget.onTap?.call(position.latitude, position.longitude);
      },
      // Native dot is opt-in (see showMyLocationDot): our custom user/driver/
      // pickup markers already cover the device position, and enabling both
      // draws two overlapping pins. The recenter button is tied to the dot —
      // showing it without the location layer would be a dead button.
      myLocationEnabled: widget.showMyLocationDot,
      myLocationButtonEnabled:
          widget.interactive && widget.showMyLocationDot,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      zoomGesturesEnabled: widget.interactive,
      scrollGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: widget.interactive,
      tiltGesturesEnabled: widget.interactive,
    );
  }
}
