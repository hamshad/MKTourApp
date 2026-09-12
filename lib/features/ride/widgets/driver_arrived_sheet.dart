import 'package:flutter/material.dart';
import '../../../core/theme.dart';

/// Compact "driver has arrived" sheet that replaces the old tall blocking
/// dialog (which overflowed on small screens / large text).
///
/// Uber/Bolt-style: success header, driver row, big license-plate card for
/// car identification, pickup hint, and a single Continue action. Content
/// scrolls inside 92% of screen height, so it can never overflow.
class DriverArrivedSheet extends StatelessWidget {
  final String driverName;
  final String rating;
  final String? profilePicture;
  final String vehicleModel;
  final String vehicleColor;
  final String vehicleNumber;
  final String pickupAddress;
  final String continueLabel;
  final VoidCallback onContinue;

  const DriverArrivedSheet({
    super.key,
    required this.driverName,
    required this.rating,
    this.profilePicture,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehicleNumber,
    required this.pickupAddress,
    required this.continueLabel,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: compact success row.
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Driver has arrived!',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$driverName is waiting for you',
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Driver row: avatar, name + rating, vehicle summary.
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryColor,
                    backgroundImage: profilePicture != null
                        ? NetworkImage(profilePicture!)
                        : null,
                    child: profilePicture == null
                        ? Text(
                            driverName.isNotEmpty ? driverName[0] : 'D',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rating,
                              style: const TextStyle(fontSize: 13),
                            ),
                            if (vehicleModel.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  vehicleColor.isNotEmpty
                                      ? '$vehicleColor · $vehicleModel'
                                      : vehicleModel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // License plate — the fastest way to spot the car.
              if (vehicleNumber.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    vehicleNumber.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Pickup hint.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.green.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pickupAddress.isNotEmpty
                            ? 'Meet at $pickupAddress'
                            : 'Head to your pickup point',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Single action.
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    continueLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
