import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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

class _PlatformMapState extends State<PlatformMap>
    with WidgetsBindingObserver {
  GoogleMapController? _controller;

  /// Native GoogleMap renders a black texture until its first frame paints
  /// (known google_maps_flutter platform-view behavior, flutter/flutter#39797).
  /// We cover that window with a neutral placeholder. onMapCreated fires when
  /// the platform CHANNEL is ready — not when tiles are drawn (flutter/flutter#54758) —
  /// so a fixed delay always races the native renderer (white -> black flash -> map
  /// on iOS). Instead we poll takeSnapshot() until the native frame actually
  /// contains map pixels, THEN fade. Fallback deadline guarantees we never stick.
  bool _showPlaceholder = true;

  /// Safety net only for the "onMapCreated never fired" failure mode.
  Timer? _placeholderSafetyTimer;

  /// Placeholder color: light neutral that matches the app's light theme, so
  /// the transition into the first map frame reads as "map loading" instead of
  /// a black flash.
  static const Color _placeholderColor = Color(0xFFF1F3F4);

  /// Last camera position we applied. Used to (a) throttle follow-animation
  /// so rapid location updates don't spam animateCamera (tiles never settle
  /// → intermittent blank map), and (b) re-assert the camera on app resume
  /// (iOS suspends the tile renderer in background → blank tiles with live
  /// markers until the camera moves).
  CameraPosition? _lastCameraPosition;

  /// Minimum displacement before the follow-camera animates again.
  static const double _followMinDistanceMeters = 15.0;

  /// Custom bitmap icons per marker key (`id + color + zoom bucket`). Filled
  /// in asynchronously; markers fall back to distinct hues until ready so
  /// pins are never all the same red.
  final Map<String, BitmapDescriptor> _icons = {};

  /// Current zoom bucket — pins shrink when zoomed out, grow when zoomed in.
  String _zoomBucket = 'mid';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Absolute fallback: if onMapCreated never fires (native view failed to
    // attach), never leave the placeholder on screen forever.
    _placeholderSafetyTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _showPlaceholder) {
        debugPrint('🗺️ PlatformMap: placeholder safety timeout fired');
        setState(() => _showPlaceholder = false);
      }
    });
    _ensureIcons();
  }

  @override
  void dispose() {
    _placeholderSafetyTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// True when [bytes] (a map snapshot) contains actual map pixels —
  /// NOT a uniform black (unpainted texture) or uniform white (empty view)
  /// frame. Samples a downsampled decode and checks luminance spread.
  static Future<bool> _frameHasMapPixels(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 32,
        targetHeight: 32,
      );
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return false;
      final pixels = data.buffer.asUint8List();
      var min = 255, max = 0, sum = 0, n = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        // Luminance of RGB; ignore alpha (empty snapshots can be opaque black).
        final lum = ((pixels[i] * 299) +
                (pixels[i + 1] * 587) +
                (pixels[i + 2] * 114)) ~/
            1000;
        if (lum < min) min = lum;
        if (lum > max) max = lum;
        sum += lum;
        n++;
      }
      if (n == 0) return false;
      final mean = sum / n;
      // Count pixels that look like map content (tiles are light-toned in the
      // default style); a handful of labels/markers over a black texture keeps
      // the lit fraction near zero.
      var lit = 0;
      var m = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        final lum = ((pixels[i] * 299) +
                (pixels[i + 1] * 587) +
                (pixels[i + 2] * 114)) ~/
            1000;
        if (lum > 25) lit++;
        m++;
      }
      if (m == 0) return false;
      final litFraction = lit / m;
      // Unpainted texture = mostly-black (low lit fraction, low mean).
      // Uniform white/empty = high lit fraction but no variation (spread ~0).
      // Real map tiles = most pixels light-toned AND visible variation.
      return litFraction > 0.35 && max - min > 20 && mean > 30;
    } catch (_) {
      // Snapshot failed (map not ready to render) — keep polling.
      return false;
    } finally {
      codec?.dispose();
    }
  }

  /// Poll the native map every 250ms until its frame actually contains map
  /// pixels, then fade the placeholder. Replaces the old fixed-delay fade that
  /// raced the renderer (revealed black texture on iOS). Hard deadline so a
  /// failed map can't leave the placeholder stuck.
  Future<void> _waitForPaintedFrame() async {
    const deadline = Duration(seconds: 6);
    final sw = Stopwatch()..start();
    // First check deferred: map view needs a beat to produce any snapshot.
    await Future.delayed(const Duration(milliseconds: 250));
    while (mounted && _showPlaceholder && sw.elapsed < deadline) {
      Uint8List? bytes;
      try {
        bytes = await _controller?.takeSnapshot();
      } catch (e) {
        // iOS throws PlatformException when snapshot is called before the
        // native map initialized — keep polling until it succeeds.
        debugPrint('🗺️ PlatformMap: snapshot not ready yet: $e');
      }
      if (bytes != null && await _frameHasMapPixels(bytes)) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (mounted && _showPlaceholder) {
      setState(() => _showPlaceholder = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS suspends the tile renderer while backgrounded: the native view
    // comes back with live markers but blank/stale tiles. Re-asserting the
    // camera forces a tile refresh.
    if (state == AppLifecycleState.resumed) {
      final controller = _controller;
      final camera = _lastCameraPosition;
      if (controller != null && camera != null) {
        controller.moveCamera(CameraUpdate.newCameraPosition(camera));
      }
    }
  }

  /// Haversine distance in meters between two points.
  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0;
    const toRad = math.pi / 180.0;
    final dLat = (lat2 - lat1) * toRad;
    final dLng = (lng2 - lng1) * toRad;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * toRad) *
            math.cos(lat2 * toRad) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthRadius * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  /// Camera targets outside the valid lat/lng range make the native renderer
  /// drop tiles. Guard every programmatic camera move.
  static bool _validTarget(double lat, double lng) =>
      !lat.isNaN &&
      !lng.isNaN &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180 &&
      (lat != 0 || lng != 0);

  @override
  void didUpdateWidget(PlatformMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_markerKeys(widget.markers).join() !=
        _markerKeys(oldWidget.markers).join()) {
      _ensureIcons();
    }
    
    // Follow the driver, but throttled: location updates arrive every few
    // seconds while driving, and spamming animateCamera keeps the tile
    // renderer perpetually loading (intermittent blank map). Only animate
    // once the target actually moved.
    if (widget.initialLat != oldWidget.initialLat || widget.initialLng != oldWidget.initialLng) {
      var shouldAnimate =
          _validTarget(widget.initialLat, widget.initialLng);
      final last = _lastCameraPosition;
      if (shouldAnimate &&
          last != null &&
          _distanceMeters(
                last.target.latitude,
                last.target.longitude,
                widget.initialLat,
                widget.initialLng,
              ) <
              _followMinDistanceMeters) {
        shouldAnimate = false;
      }
      if (shouldAnimate) {
        final next = CameraPosition(
          target: LatLng(widget.initialLat, widget.initialLng),
          zoom: 16.0,
          bearing: widget.bearing,
          tilt: widget.tilt,
        );
        _lastCameraPosition = next;
        _controller?.animateCamera(CameraUpdate.newCameraPosition(next));
      }
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
    if (!_validTarget(lat, lng)) return;

    final next = CameraPosition(
      target: LatLng(lat, lng),
      zoom: zoom ?? 16.0,
      bearing: bearing ?? 0.0,
      tilt: tilt ?? 0.0,
    );
    _lastCameraPosition = next;
    await _controller!.animateCamera(
      CameraUpdate.newCameraPosition(next),
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
        if (_validTarget(m.lat, m.lng)) {
          _controller?.moveCamera(
            CameraUpdate.newLatLngZoom(LatLng(m.lat, m.lng), 14),
          );
        }
      }
    }
  }

  String _markerKey(MapMarker m) =>
      '${m.id}_${m.markerColor?.value ?? 0}_$_zoomBucket';

  static List<String> _markerKeys(List<MapMarker> markers) =>
      markers.map((m) => '${m.id}_${m.markerColor?.value ?? 0}').toList();

  void _onCameraMove(CameraPosition position) {
    _lastCameraPosition = position;
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

    // Determine initial camera target: prefer center of bounds, fallback to initialLat/Lng.
    // Invalid targets (0,0 / NaN / out of range) make the native renderer
    // drop tiles, so fall back to London instead of passing them through.
    LatLng initialTarget = _validTarget(widget.initialLat, widget.initialLng)
        ? LatLng(widget.initialLat, widget.initialLng)
        : const LatLng(51.5085, -0.1260);
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

    return Stack(
      fit: StackFit.passthrough,
      children: [
        GoogleMap(
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
            // Seed the resume-nudge target so a background/foreground cycle
            // before any camera move still refreshes tiles.
            _lastCameraPosition ??= CameraPosition(
              target: initialTarget,
              zoom: widget.bounds != null ? 12.0 : 14.0,
              bearing: widget.bearing,
              tilt: widget.tilt,
            );
            // onMapCreated = platform channel ready, NOT tiles drawn.
            // Measure actual painted frame instead of guessing a delay.
            _placeholderSafetyTimer?.cancel();
            unawaited(_waitForPaintedFrame());
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
        ),
        // Loading cover: hides the native view's white-boot and black-paint
        // phases until real map pixels exist (measured via snapshot poll).
        // NOTE: no AnimatedOpacity here on purpose — animating opacity over an
        // iOS UiKitView/Metal layer produces black frames (that WAS the black
        // flash). Instant swap instead: placeholder present until frame is
        // measured painted, then removed in one frame.
        if (_showPlaceholder)
          Positioned.fill(
            child: IgnorePointer(
              child: const ColoredBox(
                color: _placeholderColor,
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF9AA0A6),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
