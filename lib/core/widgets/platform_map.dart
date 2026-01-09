import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;

class MapMarker {
  final String id;
  final double lat;
  final double lng;
  final Widget? child; // Not used in Google Maps but kept for API compatibility
  final String? title;

  MapMarker({
    required this.id,
    required this.lat,
    required this.lng,
    this.child,
    this.title,
  });
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
    if (_controller == null || widget.bounds == null) return;

    try {
      final bounds = widget.bounds;
      final googleBounds = LatLngBounds(
        southwest: LatLng(
          bounds.southWest.latitude,
          bounds.southWest.longitude,
        ),
        northeast: LatLng(
          bounds.northEast.latitude,
          bounds.northEast.longitude,
        ),
      );

      _controller!.animateCamera(
        CameraUpdate.newLatLngBounds(googleBounds, 100),
      );
    } catch (e) {
      debugPrint('🗺️ PlatformMap: Error fitting bounds: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🗺️ PlatformMap: Building with Google Maps');

    // Convert MapMarker to Google Maps Marker (Moved to build for reactivity)
    final googleMarkers = widget.markers.map((m) {
      return Marker(
        markerId: MarkerId(m.id),
        position: LatLng(m.lat, m.lng),
        infoWindow: InfoWindow(title: m.title ?? m.id),
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

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.initialLat, widget.initialLng),
        zoom: 14.0,
        bearing: widget.bearing,
        tilt: widget.tilt,
      ),
      markers: googleMarkers,
      polylines: googlePolylines,
      onMapCreated: (GoogleMapController controller) {
        debugPrint('🗺️ PlatformMap: Google Map created successfully');
        _controller = controller;
        if (widget.bounds != null) {
          Future.delayed(const Duration(milliseconds: 100), _fitBounds);
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
