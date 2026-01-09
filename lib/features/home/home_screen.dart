import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import 'activity_screen.dart';
import 'account_screen.dart';
import '../../core/widgets/platform_map.dart';
import '../../core/widgets/ride_searching_overlay.dart';
import '../../core/services/location_service.dart';
import '../../core/services/places_service.dart';
import 'package:latlong2/latlong.dart' as lat_lng;
import 'dart:async';
import '../../core/services/socket_service.dart';
import '../../core/api_service.dart';
import '../ride/ride_assigned_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController(viewportFraction: 0.92);
  int _currentBannerIndex = 0;

  // State variables for enhancements
  lat_lng.LatLng _currentLocation = const lat_lng.LatLng(
    51.5074,
    -0.1278,
  ); // Default London
  final LocationService _locationService = LocationService();
  final PlacesService _placesService = PlacesService();
  String? _currentAddress;
  Timer? _bannerTimer;
  bool _isMapLoading = true;

  // Booking State
  final SocketService _socketService = SocketService();
  final ApiService _apiService = ApiService();
  bool _isSearching = false;
  Map<String, dynamic>? _activeRide;
  bool _isLoading = false;

  // Connection status subscription
  StreamSubscription<bool>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _startBannerTimer();
    _setupSocketListeners();
    _setupConnectionListener();
  }

  /// Setup connection listener to re-emit user online on reconnection
  void _setupConnectionListener() {
    _connectionSubscription = _socketService.connectionStatus.listen((
      isConnected,
    ) {
      if (isConnected) {
        _emitUserOnline();
      }
    });
  }

  /// Emit user:goOnline to receive ride updates
  void _emitUserOnline() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null) {
      final userId = user['_id'] ?? user['id'] ?? user['userId'];
      if (userId != null) {
        _socketService.emitUserOnline(userId);
      }
    }
  }

  void _setupSocketListeners() {
    _socketService.initSocket().then((_) {
      _emitUserOnline();
    });

    // Listen for ride accepted event
    _socketService.on('ride:accepted', (data) {
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('✅ [HomeScreen] RIDE ACCEPTED EVENT RECEIVED');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('📦 [HomeScreen] Full data: $data');
      debugPrint('🔑 [HomeScreen] rideId: ${data['rideId'] ?? data['_id']}');
      debugPrint('🔑 [HomeScreen] otp: ${data['otp']}');
      debugPrint('🔑 [HomeScreen] verificationOTP: ${data['verificationOTP']}');
      debugPrint('👤 [HomeScreen] driver: ${data['driver']}');
      debugPrint('📍 [HomeScreen] pickupLocation: ${data['pickupLocation']}');
      debugPrint('📍 [HomeScreen] dropoffLocation: ${data['dropoffLocation']}');
      debugPrint('💰 [HomeScreen] fare: ${data['fare']}');

      if (mounted && _isSearching) {
        setState(() {
          _isSearching = false;
          _activeRide = data;
        });

        // Extract OTP from data (it's a separate field, not in driver object)
        final String otp =
            data['otp']?.toString() ??
            data['verificationOTP']?.toString() ??
            '';
        debugPrint('🔐 [HomeScreen] Extracted OTP to pass: "$otp"');

        // Build driver data with OTP included
        final Map<String, dynamic> driverWithOtp = {
          ...?(data['driver'] as Map<String, dynamic>?),
          'otp': otp,
        };
        debugPrint('👤 [HomeScreen] Driver data with OTP: $driverWithOtp');

        // Navigate to Ride Assigned Screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RideAssignedScreen(
              rideId:
                  data['rideId']?.toString() ?? data['_id']?.toString() ?? '',
              pickup: data['pickupLocation'],
              dropoff: data['dropoffLocation'],
              fare: (data['fare'] ?? 0.0).toDouble(),
              driver: driverWithOtp, // Pass driver info with OTP included
            ),
          ),
        );

        debugPrint('✅ [HomeScreen] Navigation to RideAssignedScreen initiated');
      }
    });

    // Listen for ride expired event
    _socketService.on('ride:expired', (data) {
      debugPrint('⏰ [HomeScreen] Ride Expired: $data');
      if (mounted && _isSearching) {
        setState(() {
          _isSearching = false;
          _activeRide = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ride request expired. Please try again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

    // Listen for ride cancelled event
    _socketService.on('ride:cancelled', (data) {
      debugPrint('❌ [HomeScreen] Ride Cancelled: $data');
      if (mounted && _isSearching) {
        setState(() {
          _isSearching = false;
          _activeRide = null;
        });
      }
    });

    // Listen for user status confirmation
    _socketService.on('user:status', (data) {
      debugPrint('📩 [HomeScreen] User status: $data');
    });
  }

  Future<void> _cancelRide() async {
    if (_activeRide == null) return;

    final rideId = _activeRide!['_id'] ?? _activeRide!['rideId'];
    if (rideId == null) {
      debugPrint('🔴 [HomeScreen] Cannot cancel ride: No ride ID found');
      setState(() => _isSearching = false);
      return;
    }

    debugPrint('🔵 [HomeScreen] Cancelling ride: $rideId');
    setState(() => _isLoading = true);

    try {
      final response = await _apiService.cancelRide(
        rideId,
        reason: 'user_cancelled',
      );

      if (mounted) {
        if (response['success'] == true || response['status'] == 'cancelled') {
          debugPrint('🟢 [HomeScreen] Ride cancelled successfully');
          setState(() {
            _isSearching = false;
            _activeRide = null;
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ride request cancelled'),
              backgroundColor: Colors.black87,
            ),
          );
        } else {
          debugPrint(
            '🔴 [HomeScreen] Ride cancellation failed: ${response['message']}',
          );
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to cancel ride: ${response['message'] ?? 'Unknown error'}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('🔴 [HomeScreen] Error cancelling ride: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _initLocation() async {
    debugPrint("📍 _initLocation called");
    final position = await _locationService.getCurrentLocation();
    debugPrint("📍 Position fetched: $position");
    if (position != null && mounted) {
      setState(() {
        _currentLocation = lat_lng.LatLng(
          position.latitude,
          position.longitude,
        );
        _isMapLoading = false;
      });

      // Fetch Address
      try {
        debugPrint(
          "📍 Fetching address for ${position.latitude}, ${position.longitude}",
        );
        final address = await _placesService.getAddressFromLatLng(
          position.latitude,
          position.longitude,
        );
        debugPrint("📍 Address fetched result: $address");
        if (address != null && mounted) {
          setState(() {
            _currentAddress = address;
            debugPrint("📍 _currentAddress updated to: $_currentAddress");
          });
        }
      } catch (e) {
        debugPrint("📍 Error reverse geocoding: $e");
      }
    } else {
      debugPrint("📍 Position is null or not mounted");
    }
  }

  void _startBannerTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_pageController.hasClients) {
        int nextPage = _currentBannerIndex + 1;
        if (nextPage > 2) nextPage = 0;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    // Clean up socket listeners
    _socketService.off('ride:accepted');
    _socketService.off('ride:expired');
    _socketService.off('ride:cancelled');
    _socketService.off('user:status');
    _connectionSubscription?.cancel();

    _pageController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(),
          const ActivityScreen(),
          const AccountScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF6B35),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Activity',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return Stack(
      children: [
        // 1. Live Map Background
        Positioned.fill(
          child: PlatformMap(
            initialLat: _currentLocation.latitude,
            initialLng: _currentLocation.longitude,
            markers: [
              MapMarker(
                id: 'current_loc',
                title: 'You',
                lat: _currentLocation.latitude,
                lng: _currentLocation.longitude,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Searching Overlay - Enhanced version with ride details
        if (_isSearching)
          Positioned.fill(
            child: RideSearchingOverlay(
              rideData: _activeRide,
              onCancel: _cancelRide,
              isLoading: _isLoading,
            ),
          ),

        // 2. Gradient Overlay for Header Visibility
        if (!_isSearching)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 160,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.9),
                    Colors.white.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),

        // 3. Fixed Header (Greeting & Profile)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Consumer<AuthProvider>(
                          builder: (context, auth, child) {
                            final user = auth.user;
                            final name = user?['name'] ?? 'User';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_getGreeting()}, $name! ☀️',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54,
                                    shadows: [
                                      const Shadow(
                                        color: Colors.white,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                // Address Pill
                                if (_currentAddress != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(30),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          color: Colors.red,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _currentAddress!,
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),

        // 4. Draggable Scrollable Sheet
        if (!_isSearching)
          DraggableScrollableSheet(
            initialChildSize: 0.40,
            minChildSize: 0.30,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag Handle
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Search Bar
                      GestureDetector(
                        onTap: () async {
                          final result = await Navigator.pushNamed(
                            context,
                            '/destination-search',
                          );
                          if (result != null &&
                              result is Map &&
                              result['status'] == 'searching') {
                            setState(() {
                              _isSearching = true;
                              _activeRide = result['ride'];
                            });
                          }
                        },
                        child: Hero(
                          tag: 'search_bar',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors
                                  .grey[50], // Slightly darker than white for contrast
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.search,
                                  size: 28,
                                  color: Color(0xFFFF6B35),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'Where to?',
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time_filled,
                                        size: 14,
                                        color: Colors.black87,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Now',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.keyboard_arrow_down,
                                        size: 16,
                                        color: Colors.black87,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Suggestions Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Suggestions',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: Text(
                              'See all',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFFFF6B35),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Suggestions Grid
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSuggestionCard(
                            'Ride',
                            Icons.directions_car,
                            promo: true,
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/destination-search',
                            ),
                          ),
                          _buildSuggestionCard('Package', Icons.local_shipping),
                          _buildSuggestionCard('Reserve', Icons.calendar_today),
                          _buildSuggestionCard('Intercity', Icons.commute),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Banner Carousel
                      SizedBox(
                        height: 200,
                        child: PageView(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() {
                              _currentBannerIndex = index;
                            });
                          },
                          children: [
                            _buildBannerCard(
                              title: 'Safe and reliable\ncabs for everyday.',
                              buttonText: 'Book Now',
                              image:
                                  'https://img.freepik.com/premium-vector/london-black-cab-illustration_637394-1846.jpg',
                              color: const Color(0xFFFFF3E0),
                              textColor: Colors.black87,
                            ),
                            _buildBannerCard(
                              title: '50% OFF on your\nfirst 3 rides!',
                              buttonText: 'Claim Offer',
                              image:
                                  'https://img.freepik.com/free-vector/taxi-app-concept-illustration_114360-673.jpg',
                              color: const Color(0xFFE3F2FD),
                              textColor: Colors.black87,
                            ),
                            _buildBannerCard(
                              title: 'Invite friends &\nearn rewards.',
                              buttonText: 'Invite',
                              image:
                                  'https://img.freepik.com/free-vector/refer-friend-concept-illustration_114360-7039.jpg',
                              color: const Color(0xFFE8F5E9),
                              textColor: Colors.black87,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Page Indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (index) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 8,
                            width: _currentBannerIndex == index ? 24 : 8,
                            decoration: BoxDecoration(
                              color: _currentBannerIndex == index
                                  ? const Color(0xFFFF6B35)
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 32),

                      // Recent Activity
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Activity',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: Text(
                              'See all',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFFFF6B35),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () {
                          // Action for recent activity
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                            border: Border.all(color: Colors.grey[100]!),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Color(0xFFFF6B35),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Office',
                                      style: GoogleFonts.outfit(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '2.4 km • 15 min',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Explore Section
                      Text(
                        'Explore',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildExploreCard(
                              title: 'Rentals',
                              subtitle: 'Rent by the hour',
                              icon: Icons.access_time,
                              color: const Color(0xFFE3F2FD),
                            ),
                            const SizedBox(width: 12),
                            _buildExploreCard(
                              title: 'Outstation',
                              subtitle: 'Ride out of town',
                              icon: Icons.map,
                              color: const Color(0xFFE8F5E9),
                            ),
                            const SizedBox(width: 12),
                            _buildExploreCard(
                              title: 'Electric',
                              subtitle: 'Eco-friendly rides',
                              icon: Icons.electric_car,
                              color: const Color(0xFFFFF3E0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        height: 100,
                      ), // Bottom padding for scrolling
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildBannerCard({
    required String title,
    required String buttonText,
    required String image,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -20,
            child: Opacity(
              opacity: 0.8,
              child: Image.network(
                image,
                height: 200,
                width: 200,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'PROMO',
                    style: GoogleFonts.outfit(
                      color: Colors.black87,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: textColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        buttonText,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(
    String label,
    IconData icon, {
    bool promo = false,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        ScaleButton(
          onTap: onTap,
          child: Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 32, color: const Color(0xFFFF6B35)),
                if (promo)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(20),
                          bottomLeft: Radius.circular(10),
                        ),
                      ),
                      child: Text(
                        'PROMO',
                        style: GoogleFonts.outfit(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildExploreCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    var hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }
}

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const ScaleButton({super.key, required this.child, this.onTap});

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}
