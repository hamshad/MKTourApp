import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// View data for the driver-side back-to-back offer card.
///
/// Tolerant by design: socket payloads carry nested `pickupLocation`, FCM
/// payloads carry flat `pickupAddress`/`pickupLat`/`pickupLon`, and some
/// backends send GeoJSON `{type: Point, coordinates: [lon, lat]}` with no
/// address at all. Every field resolves independently so a missing address
/// never hides the coordinates (the mini map still works) and vice versa.
class B2bOfferData {
  final String riderName;
  final String pickupAddress;
  final String dropoffAddress;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  final double fare;
  final double distance;
  final String vehicleCategory;

  const B2bOfferData({
    this.riderName = '',
    this.pickupAddress = '',
    this.dropoffAddress = '',
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.fare = 0.0,
    this.distance = 0.0,
    this.vehicleCategory = '',
  });

  bool get hasFare => fare > 0;
  bool get hasDistance => distance > 0;
  bool get hasBothPoints =>
      pickupLat != null &&
      pickupLng != null &&
      dropoffLat != null &&
      dropoffLng != null;

  String get fareLabel => hasFare ? '\£${fare.toStringAsFixed(2)}' : '';

  String get distanceLabel => hasDistance ? '${distance.toStringAsFixed(1)} mi' : '';

  /// Fallback label when the backend sends coordinates but no street address.
  String get pickupLabel => _label(pickupAddress, pickupLat, pickupLng, 'Pickup');
  String get dropoffLabel =>
      _label(dropoffAddress, dropoffLat, dropoffLng, 'Dropoff');

  static String _label(
    String address,
    double? lat,
    double? lng,
    String fallback,
  ) {
    final trimmed = address.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (lat != null && lng != null) {
      return 'Near ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }
    return fallback;
  }

  factory B2bOfferData.fromMap(Map<String, dynamic> map) {
    final pickup = _point(
      map,
      nestedKey: 'pickupLocation',
      altNestedKeys: const ['pickup', 'from', 'origin'],
      addressKey: 'pickupAddress',
      latKey: 'pickupLat',
      lngKey: 'pickupLon',
      lngAltKey: 'pickupLng',
    );
    final dropoff = _point(
      map,
      nestedKey: 'dropoffLocation',
      altNestedKeys: const ['dropoff', 'to', 'destination'],
      addressKey: 'dropoffAddress',
      latKey: 'dropoffLat',
      lngKey: 'dropoffLon',
      lngAltKey: 'dropoffLng',
    );
    final user = map['user'];
    final riderName = user is Map
        ? (user['name'] ?? user['userName'] ?? '').toString()
        : (map['userName'] ?? '').toString();
    return B2bOfferData(
      riderName: riderName.trim(),
      pickupAddress: pickup.$1,
      dropoffAddress: dropoff.$1,
      pickupLat: pickup.$2,
      pickupLng: pickup.$3,
      dropoffLat: dropoff.$2,
      dropoffLng: dropoff.$3,
      fare: _num(map['fare']) ?? 0.0,
      distance: _num(map['distance']) ?? 0.0,
      vehicleCategory:
          (map['vehicleCategorySlug'] ?? map['vehicleCategory'] ?? '')
              .toString(),
    );
  }

  /// Returns (address, lat, lng) for the requested point. Never throws.
  static (String, double?, double?) _point(
    Map<String, dynamic> map, {
    required String nestedKey,
    required List<String> altNestedKeys,
    required String addressKey,
    required String latKey,
    required String lngKey,
    required String lngAltKey,
  }) {
    dynamic raw;
    for (final key in [nestedKey, ...altNestedKeys]) {
      final candidate = map[key];
      if (candidate is Map && candidate.isNotEmpty) {
        raw = candidate;
        break;
      }
    }
    var address = '';
    double? lat;
    double? lng;
    if (raw is Map) {
      address = (raw['address'] ?? raw['formattedAddress'] ?? '').toString();
      final coords = _coords(raw);
      lat = coords?.$1;
      lng = coords?.$2;
    }
    // Flat FCM keys fill whatever the nested map did not provide.
    if (address.isEmpty) address = (map[addressKey] ?? '').toString();
    lat ??= _num(map[latKey]);
    lng ??= _num(map[lngKey]) ?? _num(map[lngAltKey]);
    // Last resort: some payloads only ship a flat coordinate pair.
    if (lat == null || lng == null) {
      final pair = _coords(map[latKey.replaceAll('Lat', 'Coordinates')]);
      if (pair != null) {
        lat ??= pair.$1;
        lng ??= pair.$2;
      }
    }
    return (address, lat, lng);
  }

  /// Extracts (lat, lng) from every shape seen in the wild: list pair,
  /// GeoJSON Point nesting, `{lat, lng}` objects, and string pairs
  /// (`"-0.1388,51.5074"` or `"51.5074,-0.1388"`).
  static (double, double)? _coords(dynamic raw) {
    dynamic coords;
    if (raw is Map) {
      coords = raw['coordinates'];
      if (coords == null) {
        final lat = _num(raw['lat'] ?? raw['latitude']);
        final lng = _num(raw['lng'] ?? raw['lon'] ?? raw['longitude']);
        if (lat != null && lng != null) return (lat, lng);
      }
    }
    if (coords is Map) coords = coords['coordinates'];
    if (coords is List && coords.length >= 2) {
      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat != null && lng != null) return (lat, lng);
    }
    if (coords is String) {
      final parts = coords
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('(', '')
          .replaceAll(')', '')
          .split(',')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        final a = double.tryParse(parts[0]);
        final b = double.tryParse(parts[1]);
        if (a != null && b != null) {
          // Strings follow GeoJSON order: [lng, lat]. A first value outside
          // [-90, 90] can only be a longitude, which the same order honours.
          return (b, a);
        }
      }
    }
    return null;
  }

  static double? _num(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Queued-trip banner the driver can swipe away.
///
/// Swipe up (or tap the chevron) to hand the queued trip to the bottom-sheet
/// row — exactly one surface shows it at a time. Keyed by ride id so a new
/// queued trip always gets a fresh, un-dismissed banner.
class B2bDismissibleBanner extends StatelessWidget {
  final String rideId;
  final Widget child;
  final VoidCallback onDismissed;

  const B2bDismissibleBanner({
    super.key,
    required this.rideId,
    required this.child,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('b2b-banner-$rideId'),
      direction: DismissDirection.up,
      dismissThresholds: const {DismissDirection.up: 0.35},
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              const Text(
                'Move to trip panel',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Uber/Bolt-style mini route preview: pickup → dropoff with the driver's
/// current position when known. Painted locally (no map tiles, no second
/// platform view) so it stays cheap, deterministic and never blank on iOS.
class B2bRoutePreview extends StatelessWidget {
  final B2bOfferData data;
  final double? driverLat;
  final double? driverLng;
  final double height;

  const B2bRoutePreview({
    super.key,
    required this.data,
    this.driverLat,
    this.driverLng,
    this.height = 104,
  });

  @override
  Widget build(BuildContext context) {
    if (!data.hasBothPoints) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Route preview unavailable',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _RoutePreviewPainter(
            pickupLat: data.pickupLat!,
            pickupLng: data.pickupLng!,
            dropoffLat: data.dropoffLat!,
            dropoffLng: data.dropoffLng!,
            driverLat: driverLat,
            driverLng: driverLng,
            routeColor: AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final double? driverLat;
  final double? driverLng;
  final Color routeColor;

  _RoutePreviewPainter({
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.driverLat,
    required this.driverLng,
    required this.routeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backdrop = Paint()..color = const Color(0xFFF1F3F6);
    canvas.drawRect(Offset.zero & size, backdrop);

    final grid = Paint()
      ..color = const Color(0xFFE2E6EC)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final points = [
      _project(pickupLat, pickupLng, size),
      _project(dropoffLat, dropoffLng, size),
    ];
    if (driverLat != null && driverLng != null) {
      points.add(_project(driverLat!, driverLng!, size));
    }

    // Route line sits under every marker.
    if (points.length >= 2) {
      final route = Paint()
        ..color = routeColor.withValues(alpha: 0.85)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, route);
    }

    _drawPin(canvas, points[0], Colors.black87, filled: true);
    _drawPin(canvas, points[1], const Color(0xFFE23D3D), filled: true);
    if (points.length > 2) {
      _drawDriver(canvas, points[2]);
    }
  }

  Offset _project(double lat, double lng, Size size) {
    final lats = <double>[pickupLat, dropoffLat];
    final lngs = <double>[pickupLng, dropoffLng];
    if (driverLat != null) lats.add(driverLat!);
    if (driverLng != null) lngs.add(driverLng!);
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);
    const pad = 22.0;
    final latSpan = math.max(maxLat - minLat, 0.002);
    final lngSpan = math.max(maxLng - minLng, 0.002);
    final x = pad + (lng - minLng) / lngSpan * (size.width - pad * 2);
    final y =
        size.height - pad - (lat - minLat) / latSpan * (size.height - pad * 2);
    return Offset(x, y);
  }

  void _drawPin(Canvas canvas, Offset at, Color color, {required bool filled}) {
    canvas.drawCircle(
      at,
      8,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(at, 5.5, Paint()..color = color);
    if (!filled) return;
    canvas.drawCircle(
      at,
      5.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawDriver(Canvas canvas, Offset at) {
    canvas.drawCircle(at, 9, Paint()..color = Colors.white);
    canvas.drawCircle(at, 6, Paint()..color = const Color(0xFF111827));
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter old) {
    return old.pickupLat != pickupLat ||
        old.pickupLng != pickupLng ||
        old.dropoffLat != dropoffLat ||
        old.dropoffLng != dropoffLng ||
        old.driverLat != driverLat ||
        old.driverLng != driverLng;
  }
}

/// Non-intrusive back-to-back offer for a driver already on a trip.
///
/// Reference anatomy (Uber / Bolt / Lyft driver surfaces): rider identity +
/// fare up top, route preview, pickup→dropoff timeline, then a quiet
/// secondary action beside one strong primary CTA. The card floats over the
/// map — the active trip keeps navigation and all its controls.
class B2bOfferCard extends StatefulWidget {
  final B2bOfferData data;
  final bool busy;
  final bool enriching;
  final String? error;
  final double? driverLat;
  final double? driverLng;
  final VoidCallback onQueue;
  final VoidCallback onSkip;

  const B2bOfferCard({
    super.key,
    required this.data,
    required this.onQueue,
    required this.onSkip,
    this.busy = false,
    this.enriching = false,
    this.error,
    this.driverLat,
    this.driverLng,
  });

  @override
  State<B2bOfferCard> createState() => _B2bOfferCardState();
}

class _B2bOfferCardState extends State<B2bOfferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  bool _queuePressed = false;
  bool _skipPressed = false;

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final curve = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - curve.value)),
          child: child,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.10,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.repeat_rounded,
                                size: 16,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                data.riderName.isEmpty
                                    ? 'New ride near your dropoff'
                                    : data.riderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _MetaRow(data: data),
                      ],
                    ),
                  ),
                  if (data.hasFare) ...[
                    const SizedBox(width: 12),
                    Text(
                      data.fareLabel,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: B2bRoutePreview(
                data: data,
                driverLat: widget.driverLat,
                driverLng: widget.driverLng,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _RouteTimeline(data: data),
            ),
            if (widget.enriching)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Row(
                  children: [
                    const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading pickup details…',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  widget.error!,
                  style: const TextStyle(
                    color: Color(0xFFD32F2F),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _PressableScale(
                      pressed: _skipPressed,
                      onTap: widget.busy ? null : _onSkip,
                      child: _SecondaryButton(
                        label: 'Skip',
                        onPressed: widget.busy ? null : _onSkip,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _PressableScale(
                      pressed: _queuePressed,
                      onTap: widget.busy ? null : _onQueue,
                      child: _PrimaryButton(
                        label: 'Queue trip',
                        busy: widget.busy,
                        onPressed: widget.busy ? null : _onQueue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onQueue() {
    setState(() => _queuePressed = true);
    widget.onQueue();
  }

  void _onSkip() {
    setState(() => _skipPressed = true);
    widget.onSkip();
  }
}

class _MetaRow extends StatelessWidget {
  final B2bOfferData data;
  const _MetaRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'New request',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (data.hasDistance) ...[
          const Text(
            '  ·  ',
            style: TextStyle(fontSize: 13, color: Colors.black26),
          ),
          Text(
            data.distanceLabel,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (data.vehicleCategory.isNotEmpty) ...[
          const Text(
            '  ·  ',
            style: TextStyle(fontSize: 13, color: Colors.black26),
          ),
          Flexible(
            child: Text(
              _titleCase(data.vehicleCategory),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _titleCase(String slug) {
    if (slug.isEmpty) return slug;
    return slug
        .split(RegExp(r'[_\-\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}

class _RouteTimeline extends StatelessWidget {
  final B2bOfferData data;
  const _RouteTimeline({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TimelineRow(
          icon: const _PickupDot(),
          text: data.pickupLabel,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 9),
          child: Container(
            width: 2,
            height: 14,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
        _TimelineRow(
          icon: const Icon(
            Icons.flag_rounded,
            size: 18,
            color: Color(0xFFE23D3D),
          ),
          text: data.dropoffLabel,
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final Widget icon;
  final String text;
  const _TimelineRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 20, height: 20, child: Center(child: icon)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.25,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _PickupDot extends StatelessWidget {
  const _PickupDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.35),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primaryColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 48,
          child: Center(
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F3F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tactile press feedback: 0.96 scale, interruptible, 40px+ hit area.
class _PressableScale extends StatefulWidget {
  final bool pressed;
  final Widget child;
  final VoidCallback? onTap;
  const _PressableScale({
    required this.pressed,
    required this.child,
    this.onTap,
  });

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final active = _down || widget.pressed;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: active ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
