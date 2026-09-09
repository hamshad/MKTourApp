import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';

/// A full-screen overlay shown when searching for a driver
/// Displays animated searching indicator, ride details, and cancel button.
///
/// Three states (new ride flow):
/// - searching: animated pulse + cancel CTA (default, [reassignmentCount] == 0)
/// - reassigning: info banner "Finding you another driver…" with
///   [reassignmentCount], keeps the cancel CTA, rider stays in flow
/// - expired: no driver found → retry CTA ([isExpired] + [onRetry])
class RideSearchingOverlay extends StatefulWidget {
  final Map<String, dynamic>? rideData;
  final VoidCallback onCancel;
  final VoidCallback? onTimerEnd; // Added callback for expiration
  final bool isLoading;

  /// > 0 while the backend auto-reassigns after a driver cancel.
  /// Shows the reassigning banner instead of the plain searching copy.
  final int reassignmentCount;

  /// True when the request expired with no driver — shows retry CTA.
  final bool isExpired;
  final VoidCallback? onRetry;

  const RideSearchingOverlay({
    super.key,
    this.rideData,
    required this.onCancel,
    this.onTimerEnd,
    this.isLoading = false,
    this.reassignmentCount = 0,
    this.isExpired = false,
    this.onRetry,
  });

  @override
  State<RideSearchingOverlay> createState() => _RideSearchingOverlayState();
}

class _RideSearchingOverlayState extends State<RideSearchingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  int _dotCount = 0;
  Timer? _dotTimer;
  int _remainingSeconds = 300; // 5 minutes

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startDotAnimation();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startDotAnimation() {
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {
          _dotCount = (_dotCount + 1) % 4;
        });
      }
    });
  }


  String get _formattedTime => "05:00"; // Placeholder or remove usage

  @override
  void dispose() {
    _pulseController.dispose();
    _dotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasData = widget.rideData != null;
    final pickupAddress =
        widget.rideData?['pickupLocation']?['address'] ?? 'Pickup';
    final dropoffAddress =
        widget.rideData?['dropoffLocation']?['address'] ?? 'Destination';
    final fare = widget.rideData?['fare'] ?? 0;
    final distance = widget.rideData?['distance'] ?? 0;
    final isReassigning = widget.reassignmentCount > 0 && !widget.isExpired;

    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Stack(
        children: [
          // Background Blur for premium feel
          Positioned.fill(
            child: BackdropFilter(
              filter: ColorFilter.mode(
                Colors.black.withOpacity(0.3),
                BlendMode.darken,
              ),
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const SizedBox(height: 56),

                          const SizedBox(height: 40),

                          // Animated car icon with pulse
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pulseAnimation.value,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6B35).withOpacity(
                                      0.15,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFFF6B35,
                                        ).withOpacity(0.3),
                                        blurRadius: 30,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 90,
                                      height: 90,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFF6B35),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.local_taxi,
                                        color: Colors.white,
                                        size: 45,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 40),

                          // Finding driver text
                          if (widget.isExpired)
                            Text(
                              'No driver found',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            )
                          else
                            Text(
                              isReassigning
                                  ? 'Finding you another driver${'.' * _dotCount}'
                                  : 'Finding your driver${'.' * _dotCount}',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),

                          const SizedBox(height: 12),

                          if (isReassigning)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.autorenew,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Your driver cancelled — attempt ${widget.reassignmentCount}. Stay here, matching continues.',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              widget.isExpired
                                  ? 'No nearby drivers accepted in time'
                                  : 'Connecting you with nearby drivers',
                              style: GoogleFonts.outfit(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),

                          const Spacer(),

                          // Trip summary card with glassmorphism.
                          // No data yet → loading skeleton (never a bare
                          // spinner or empty card).
                          if (!hasData)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 24),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),
                              child: Column(
                                children: [
                                  _buildSkeletonRow(),
                                  _buildSkeletonRow(),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Divider(color: Colors.white12),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildSkeletonBox(110),
                                      _buildSkeletonBox(80),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          else
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.12),
                              ),
                            ),
                            child: Column(
                              children: [
                                // Locations
                                _buildLocationRow(
                                  Colors.green,
                                  pickupAddress,
                                  isLast: false,
                                ),
                                _buildLocationRow(
                                  Colors.red,
                                  dropoffAddress,
                                  isLast: true,
                                ),

                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Divider(color: Colors.white12),
                                ),

                                // Fare and distance (£, 2 decimals — same
                                // language as receipt + progress screens)
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildInfoColumn('Estimated Fare',
                                        '£${_asDouble(fare).toStringAsFixed(2)}'),
                                    _buildInfoColumn('Distance',
                                        '${_asDouble(distance).toStringAsFixed(1)} mi'),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const Spacer(),

                          // Cancel button
                          Padding(
                            padding: EdgeInsets.only(
                              left: 24,
                              right: 24,
                              top: 24,
                              bottom: 32 + MediaQuery.of(context).padding.bottom,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Expired → retry CTA (keeps cancel below)
                                if (widget.isExpired)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: widget.isLoading
                                          ? null
                                          : (widget.onRetry ??
                                              widget.onTimerEnd),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFFF6B35,
                                        ),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: widget.isLoading
                                          ? const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                                SizedBox(width: 10),
                                                Text(
                                                  'Retrying…',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : const FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                'Try Again',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                if (widget.isExpired) const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: OutlinedButton(
                                    onPressed: widget.isLoading
                                        ? null
                                        : widget.onCancel,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: widget.isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'Cancel Request',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Loading skeleton row — shimmering placeholder while ride data loads.
  Widget _buildSkeletonRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildSkeletonBox(double.infinity)),
        ],
      ),
    );
  }

  Widget _buildSkeletonBox(double width) {
    return Container(
      width: width == double.infinity ? null : width,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildLocationRow(Color color, String address, {bool isLast = false}) {    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withOpacity(0.5), Colors.white10],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            address,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment:
          label == 'Distance' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
