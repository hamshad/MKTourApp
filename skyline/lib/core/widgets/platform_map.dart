import 'dart:io';
import 'package:flutter/material.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart' as latlong;

class MapMarker {
  final String id;
  final double lat;
  final double lng;
  final Widget? child; // For Flutter Map
  final String? title; // For Apple Map

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
  final fmap.LatLngBounds? bounds;

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
  apple.AppleMapController? _appleController;
  final fmap.MapController _flutterController = fmap.MapController();

  @override
  void didUpdateWidget(PlatformMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bounds != null && widget.bounds != oldWidget.bounds) {
      _fitBounds(widget.bounds!);
    }
  }

  void _fitBounds(fmap.LatLngBounds bounds) {
    if (Platform.isIOS && _appleController != null) {
      final appleBounds = apple.LatLngBounds(
        southwest: apple.LatLng(bounds.southWest.latitude, bounds.southWest.longitude),
        northeast: apple.LatLng(bounds.northEast.latitude, bounds.northEast.longitude),
      );
      _appleController!.animateCamera(apple.CameraUpdate.newLatLngBounds(appleBounds, 50));
    } else if (!Platform.isIOS) {
      _flutterController.fitCamera(
        fmap.CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🗺️ PlatformMap: Building. Platform: ${Platform.operatingSystem}');

    if (Platform.isIOS) {
      debugPrint('🗺️ PlatformMap: Rendering AppleMap');
      final annotations = widget.markers.map((m) {
        return apple.Annotation(
          annotationId: apple.AnnotationId(m.id),
          position: apple.LatLng(m.lat, m.lng),
          infoWindow: apple.InfoWindow(title: m.title ?? 'Marker'),
        );
      }).toSet();

      final applePolylines = widget.polylines.map((p) {
        return apple.Polyline(
          polylineId: apple.PolylineId(p.id),
          points: p.points.map((pt) => apple.LatLng(pt.latitude, pt.longitude)).toList(),
          color: p.color,
          width: p.width.toInt(),
        );
      }).toSet();

      return apple.AppleMap(
        initialCameraPosition: apple.CameraPosition(
          target: apple.LatLng(widget.initialLat, widget.initialLng),
          zoom: 14.0,
        ),
        annotations: annotations,
        polylines: applePolylines,
        onMapCreated: (apple.AppleMapController controller) {
          debugPrint('🗺️ PlatformMap: AppleMap created successfully');
          _appleController = controller;
          if (widget.bounds != null) {
            _fitBounds(widget.bounds!);
          }
        },
        onTap: (apple.LatLng position) {
          debugPrint('🗺️ PlatformMap: AppleMap tapped at ${position.latitude}, ${position.longitude}');
          widget.onTap?.call(position.latitude, position.longitude);
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      );
    } else {
      debugPrint('🗺️ PlatformMap: Rendering FlutterMap');
      final flutterMarkers = widget.markers.map((m) {
        return fmap.Marker(
          point: latlong.LatLng(m.lat, m.lng),
          width: 40,
          height: 40,
          child: m.child ?? const Icon(Icons.location_on, color: Colors.red, size: 40),
        );
      }).toList();

      final flutterPolylines = widget.polylines.map((p) {
        return fmap.Polyline(
          points: p.points,
          color: p.color,
          strokeWidth: p.width,
        );
      }).toList();

      return fmap.FlutterMap(
        mapController: _flutterController,
        options: fmap.MapOptions(
          initialCenter: latlong.LatLng(widget.initialLat, widget.initialLng),
          initialZoom: 14.0,
          onTap: (tapPosition, point) {
            debugPrint('🗺️ PlatformMap: FlutterMap tapped at ${point.latitude}, ${point.longitude}');
            widget.onTap?.call(point.latitude, point.longitude);
          },
          onMapReady: () {
             if (widget.bounds != null) {
              _fitBounds(widget.bounds!);
            }
          },
        ),
        children: [
          fmap.TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.mktours.app',
          ),
          fmap.MarkerLayer(
            markers: flutterMarkers,
          ),
          fmap.PolylineLayer(
            polylines: flutterPolylines,
          ),
        ],
      );
    }
  }
}
