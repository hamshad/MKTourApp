import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as latlong;
import '../models/vehicle.dart';
import 'platform_map.dart';

/// Shared multi-stop map styling, inspired by Uber / Bolt:
/// - Thick dark route with a light casing underneath so it pops on any map.
/// - Numbered white stop pins with a dark ring (Uber-style).
/// - Completed stops turn green, the next stop pulses blue.

class RouteMapHelpers {
  const RouteMapHelpers._();

  /// Extract usable stop coordinates from any ride payload shape.
  /// Accepts `RideStop`s, API maps (`coordinates: [lng, lat]`), or
  /// flat maps (`lat`/`lng`). Returns [latlong.LatLng] in stop order.
  static List<latlong.LatLng> stopPoints(List<dynamic> stops) {
    final points = <latlong.LatLng>[];
    for (final stop in stops) {
      double? lat;
      double? lng;
      if (stop is RideStop) {
        final c = stop.coordinates;
        if (c != null && c.length >= 2) {
          lng = c[0];
          lat = c[1];
        }
      } else if (stop is Map) {
        final m = Map<String, dynamic>.from(stop);
        final coords = m['coordinates'];
        if (coords is List && coords.length >= 2) {
          lng = (coords[0] as num?)?.toDouble();
          lat = (coords[1] as num?)?.toDouble();
        }
        lat ??= (m['lat'] as num?)?.toDouble();
        lng ??= (m['lng'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;
      if (lat == 0.0 && lng == 0.0) continue;
      if (lat.isNaN || lng.isNaN) continue;
      points.add(latlong.LatLng(lat, lng));
    }
    return points;
  }

  /// Numbered stop markers (Uber/Bolt style).
  ///
  /// [statuses] optionally carries each stop's status
  /// (`pending`/`arrived`/`completed`) to tint the badge: white with a black
  /// number while pending, blue when arrived, green when completed.
  /// [PlatformMap] renders the number as a bitmap badge; [markerColor] below
  /// carries the tint (plus an instant hue fallback while it generates).
  static List<MapMarker> stopMarkers(
    List<dynamic> stops, {
    List<String>? statuses,
  }) {
    final points = stopPoints(stops);
    return List.generate(points.length, (i) {
      final status = (statuses != null && i < statuses.length)
          ? statuses[i]
          : RideStopStatus.pending;
      final Color badge;
      if (status == RideStopStatus.completed) {
        badge = const Color(0xFF16A34A);
      } else if (status == RideStopStatus.arrived) {
        badge = const Color(0xFF2563EB);
      } else {
        badge = Colors.white;
      }
      return MapMarker(
        id: 'stop_${i + 1}',
        lat: points[i].latitude,
        lng: points[i].longitude,
        title: 'Stop ${i + 1}',
        markerColor: badge,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: badge,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
          child: Center(
            child: Text(
              '${i + 1}',
              style: TextStyle(
                color: badge == Colors.white ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    });
  }

  /// Cased route polylines: a wide light casing + the dark main line.
  /// Pass [completedUpTo] (polyline index) to render the travelled part
  /// in grey and the remainder in black — Bolt-style progress.
  static List<MapPolyline> routePolylines(
    List<latlong.LatLng> points, {
    Color color = Colors.black,
    int? completedUpTo,
  }) {
    if (points.isEmpty) return [];
    if (completedUpTo != null &&
        completedUpTo > 0 &&
        completedUpTo < points.length) {
      final done = points.sublist(0, completedUpTo + 1);
      final rest = points.sublist(completedUpTo);
      return [
        MapPolyline(
          id: 'route_done',
          points: done,
          color: Colors.grey.shade400,
          width: 5.0,
        ),
        MapPolyline(
          id: 'route_casing',
          points: rest,
          color: Colors.white,
          width: 8.0,
        ),
        MapPolyline(id: 'route', points: rest, color: color, width: 5.0),
      ];
    }
    return [
      MapPolyline(
        id: 'route_casing',
        points: points,
        color: Colors.white,
        width: 8.0,
      ),
      MapPolyline(id: 'route', points: points, color: color, width: 5.0),
    ];
  }

  /// Bounds that fit origin, destination, and every stop.
  static List<latlong.LatLng> boundsPoints({
    required latlong.LatLng origin,
    required latlong.LatLng destination,
    List<dynamic>? stops,
  }) {
    return [
      origin,
      destination,
      if (stops != null) ...stopPoints(stops),
    ];
  }
}
