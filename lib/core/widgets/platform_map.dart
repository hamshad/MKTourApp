import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;

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
  });

  @override
  State<PlatformMap> createState() => _PlatformMapState();
}

class _PlatformMapState extends State<PlatformMap> {
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(PlatformMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    
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
      final bounds = widget.bounds;
      final swLat = bounds.southWest.latitude;
      final swLng = bounds.southWest.longitude;
      final neLat = bounds.northEast.latitude;
      final neLng = bounds.northEast.longitude;
      
      debugPrint('🗺️ PlatformMap: Fitting bounds...');
      debugPrint('   → SW: ($swLat, $swLng)');
      debugPrint('   → NE: ($neLat, $neLng)');
      
      // Calculate center point
      final centerLat = (swLat + neLat) / 2;
      final centerLng = (swLng + neLng) / 2;
      
      debugPrint('   → Center: ($centerLat, $centerLng)');
      
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

  @override
  Widget build(BuildContext context) {
    debugPrint('🗺️ PlatformMap: Building with Google Maps');
    debugPrint('   → Markers: ${widget.markers.length}');
    debugPrint('   → Polylines: ${widget.polylines.length}');
    if (widget.polylines.isNotEmpty) {
      debugPrint('   → First polyline points: ${widget.polylines.first.points.length}');
    }

    // Convert MapMarker to Google Maps Marker (Moved to build for reactivity)
    final googleMarkers = widget.markers.map((m) {
      return Marker(
        markerId: MarkerId(m.id),
        position: LatLng(m.lat, m.lng),
        infoWindow: InfoWindow(title: m.title ?? m.id),
        // Use custom colored marker if markerColor is specified
        icon: m.markerHue != null
            ? BitmapDescriptor.defaultMarkerWithHue(m.markerHue!)
            : BitmapDescriptor.defaultMarker,
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
      initialTarget = LatLng(
        (widget.bounds.southWest.latitude + widget.bounds.northEast.latitude) / 2,
        (widget.bounds.southWest.longitude + widget.bounds.northEast.longitude) / 2,
      );
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
      myLocationEnabled: widget.interactive,
      myLocationButtonEnabled: widget.interactive,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      zoomGesturesEnabled: widget.interactive,
      scrollGesturesEnabled: widget.interactive,
      rotateGesturesEnabled: widget.interactive,
      tiltGesturesEnabled: widget.interactive,
    );
  }
}
