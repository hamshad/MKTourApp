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

  const PlatformMap({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.onTap,
    this.markers = const [],
    this.polylines = const [],
    this.bounds,
  });

  @override
  State<PlatformMap> createState() => _PlatformMapState();
}

class _PlatformMapState extends State<PlatformMap> {
  GoogleMapController? _controller;
  Set<Marker> _googleMarkers = {};
  Set<Polyline> _googlePolylines = {};

  @override
  void initState() {
    super.initState();
    _updateMapObjects();
  }

  @override
  void didUpdateWidget(PlatformMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMapObjects();
    
    // Animate to new location if coordinates changed
    if (widget.initialLat != oldWidget.initialLat || widget.initialLng != oldWidget.initialLng) {
      _controller?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(widget.initialLat, widget.initialLng),
        ),
      );
    }
    
    if (widget.bounds != null && widget.bounds != oldWidget.bounds) {
      _fitBounds();
    }
  }

  void _updateMapObjects() {
    // Convert MapMarker to Google Maps Marker
    _googleMarkers = widget.markers.map((m) {
      return Marker(
        markerId: MarkerId(m.id),
        position: LatLng(m.lat, m.lng),
        infoWindow: InfoWindow(title: m.title ?? m.id),
      );
    }).toSet();

    // Convert MapPolyline to Google Maps Polyline
    _googlePolylines = widget.polylines.map((p) {
      return Polyline(
        polylineId: PolylineId(p.id),
        points: p.points.map((pt) => LatLng(pt.latitude, pt.longitude)).toList(),
        color: p.color,
        width: p.width.toInt(),
      );
    }).toSet();
  }

  void _fitBounds() {
    if (_controller == null || widget.bounds == null) return;

    try {
      // Create LatLngBounds for Google Maps
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

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.initialLat, widget.initialLng),
        zoom: 14.0,
      ),
      markers: _googleMarkers,
      polylines: _googlePolylines,
      onMapCreated: (GoogleMapController controller) {
        debugPrint('🗺️ PlatformMap: Google Map created successfully');
        _controller = controller;
        if (widget.bounds != null) {
          // Delay to ensure map is fully loaded before fitting bounds
          Future.delayed(const Duration(milliseconds: 100), _fitBounds);
        }
      },
      onTap: (LatLng position) {
        debugPrint('🗺️ PlatformMap: Map tapped at ${position.latitude}, ${position.longitude}');
        widget.onTap?.call(position.latitude, position.longitude);
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
    );
  }
}
