import 'package:flutter/material.dart';

import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import '../../core/theme.dart';
import '../../core/widgets/platform_map.dart';
import 'driver_request_panel.dart';
import 'driver_navigation_panel.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../../core/network/api_service.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  // Status: offline, online, request, pickup, arrived, in_progress, complete
  String _status = 'offline';
  final PanelController _panelController = PanelController();
  
  // Mock location
  LatLng _currentLocation = const LatLng(51.5085, -0.1260);

  final ApiService _apiService = ApiService();

  Future<void> _toggleOnline() async {
    final bool isGoingOnline = _status == 'offline';
    
    try {
      debugPrint('🔵 [DriverHomeScreen] Toggling status. Current: $_status, Target: ${isGoingOnline ? 'online' : 'offline'}');
      
      // Show loading indicator if needed, or just optimistically update
      // For now, we'll wait for the API response to be sure
      
      final response = await _apiService.updateDriverStatus(isGoingOnline);
      
      if (response['success'] == true) {
        setState(() {
          _status = isGoingOnline ? 'online' : 'offline';
        });
        
        if (mounted) {
          CustomSnackbar.show(
            context,
            message: response['message'] ?? (isGoingOnline ? 'You are now Online' : 'You are now Offline'),
            type: SnackbarType.success,
          );
        }
        debugPrint('🟢 [DriverHomeScreen] Status updated successfully to $_status');
      } else {
        if (mounted) {
          CustomSnackbar.show(
            context,
            message: 'Failed to update status: ${response['message']}',
            type: SnackbarType.error,
          );
        }
        debugPrint('🔴 [DriverHomeScreen] Failed to update status');
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Error updating status: $e',
          type: SnackbarType.error,
        );
      }
      debugPrint('🔴 [DriverHomeScreen] Error updating status: $e');
    }
  }

  void _simulateRequest() {
    if (_status == 'online') {
      setState(() => _status = 'request');
    } else {
      CustomSnackbar.show(
        context,
        message: 'You must be online to receive requests',
        type: SnackbarType.warning,
      );
    }
  }

  void _handleRideAction() {
    if (_status == 'arrived') {
      _showOtpDialog();
      return;
    }

    setState(() {
      switch (_status) {
        case 'request':
          _status = 'pickup';
          break;
        case 'pickup':
          _status = 'arrived';
          break;
        case 'in_progress':
          _status = 'complete';
          // Reset to online after short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _status = 'online');
          });
          break;
      }
    });
  }

  void _showOtpDialog() {
    final TextEditingController otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter OTP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ask passenger for the 4-digit PIN'),
            const SizedBox(height: 16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: '0000',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (otpController.text == '1234') { // Mock OTP
                Navigator.pop(context);
                setState(() => _status = 'in_progress');
                CustomSnackbar.show(
                  context,
                  message: 'OTP Verified! Trip Started.',
                  type: SnackbarType.success,
                );
              } else {
                CustomSnackbar.show(
                  context,
                  message: 'Invalid OTP. Try 1234',
                  type: SnackbarType.error,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify & Start'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          // Map
          PlatformMap(
            initialLat: _currentLocation.latitude,
            initialLng: _currentLocation.longitude,
            markers: [
              MapMarker(
                id: 'driver',
                lat: _currentLocation.latitude,
                lng: _currentLocation.longitude,
                child: const Icon(Icons.directions_car, color: AppTheme.primaryColor, size: 40),
                title: 'Driver',
              ),
              if (_status == 'pickup' || _status == 'in_progress')
                MapMarker(
                  id: 'destination',
                  lat: 51.5074,
                  lng: -0.1278,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                  title: 'Destination',
                ),
            ],
            polylines: [
              if (_status == 'pickup' || _status == 'in_progress')
                MapPolyline(
                  id: 'route',
                  points: [_currentLocation, const LatLng(51.5074, -0.1278)],
                  color: AppTheme.primaryColor,
                  width: 4.0,
                ),
            ],
          ),
          
          // Top Bar (Earnings & Status)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Earnings Pill
                      GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/driver-earnings'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: AppTheme.primaryColor),
                              SizedBox(width: 8),
                              Text(
                                '£142.50',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Profile Button
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        child: IconButton(
                          icon: const Icon(Icons.person, color: Colors.black),
                          onPressed: () => Navigator.pushNamed(context, '/driver-profile'),
                        ),
                      ),
                    ],
                  ),
                  if (_status == 'online') ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _simulateRequest,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Simulate Request'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.primaryColor,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Bottom UI based on Status
          if (_status == 'offline' || _status == 'online')
            _buildOfflineOnlinePanel(context)
          else if (_status == 'request')
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: DriverRequestPanel(
                onAccept: _handleRideAction,
                onDecline: () => setState(() => _status = 'online'),
              ),
            )
          else
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: DriverNavigationPanel(
                status: _status,
                onAction: _handleRideAction,
              ),
            ),
            
          // Complete Trip Overlay
          if (_status == 'complete')
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  margin: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Trip Completed!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You earned £14.50',
                        style: TextStyle(
                          fontSize: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOfflineOnlinePanel(BuildContext context) {
    return SlidingUpPanel(
      controller: _panelController,
      minHeight: 160,
      maxHeight: 400,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      panel: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Go Online Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: _toggleOnline,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: _status == 'online' ? Colors.red : AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: (_status == 'online' ? Colors.red : AppTheme.primaryColor).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _status == 'online' ? 'GO OFFLINE' : 'GO ONLINE',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Stats / Recent Activity
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Today\'s Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/driver-activity'),
                      child: const Text('See All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatCard('Trips', '12', Icons.directions_car),
                    const SizedBox(width: 16),
                    _buildStatCard('Hours', '4.5', Icons.access_time),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildActivityItem('Heathrow Drop-off', '£24.50', '10:30 AM'),
                _buildActivityItem('City Center Ride', '£12.20', '09:15 AM'),
                _buildActivityItem('Morning Commute', '£8.50', '08:45 AM'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String title, String amount, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.history, color: AppTheme.textPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
