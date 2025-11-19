import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import '../../core/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _nearbyCarCount = 12;
  final PageController _promoController = PageController();
  Timer? _promoTimer;
  int _currentPromoPage = 0;
  
  final LatLng _center = const LatLng(51.5074, -0.1278);
  
  final List<LatLng> _taxis = [
    const LatLng(51.5080, -0.1280),
    const LatLng(51.5070, -0.1270),
    const LatLng(51.5090, -0.1260),
  ];
  
  final List<Map<String, String>> _recentPlaces = [
    {'name': 'Heathrow Terminal 5', 'address': 'Longford TW6, UK', 'icon': '✈️'},
    {'name': 'The Shard', 'address': 'London Bridge, SE1', 'icon': '🏢'},
    {'name': 'King\'s Cross Station', 'address': 'Kings Cross, N1', 'icon': '🚉'},
  ];
  
  final List<Map<String, dynamic>> _promos = [
    {
      'color': Color(0xFFF3E5F5),
      'icon': Icons.local_offer,
      'iconColor': Color(0xFF9C27B0),
      'title': '20% Off',
      'subtitle': 'On your next 3 rides',
      'cta': 'Claim Now',
    },
    {
      'color': Color(0xFFE3F2FD),
      'icon': Icons.card_giftcard,
      'iconColor': Color(0xFF2196F3),
      'title': 'Refer & Earn',
      'subtitle': 'Get £10 for each friend',
      'cta': 'Share',
    },
    {
      'color': Color(0xFFFFF3E0),
      'icon': Icons.trending_down,
      'iconColor': Color(0xFFFF9800),
      'title': 'Low Fares',
      'subtitle': 'Save up to 30% today',
      'cta': 'View Deals',
    },
  ];

  @override
  void initState() {
    super.initState();
    print('🏠 HOME SCREEN: Loaded');
    _startPromoAutoScroll();
    _updateCarCount();
  }

  @override
  void dispose() {
    _promoTimer?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  void _startPromoAutoScroll() {
    _promoTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPromoPage < _promos.length - 1) {
        _currentPromoPage++;
      } else {
        _currentPromoPage = 0;
      }
      _promoController.animateToPage(
        _currentPromoPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _updateCarCount() {
    // Simulate car count updates
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        setState(() {
          _nearbyCarCount = 8 + (DateTime.now().second % 8);
        });
      }
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  bool _shouldShowWorkSuggestion() {
    final now = DateTime.now();
    final hour = now.hour;
    final isWeekday = now.weekday >= 1 && now.weekday <= 5;
    return isWeekday && hour >= 8 && hour <= 10;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Map fills screen
          FlutterMap(
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.skyline',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _center,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ..._taxis.map((pos) => Marker(
                        point: pos,
                        width: 36,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.local_taxi,
                            color: AppTheme.textPrimary,
                            size: 20,
                          ),
                        ),
                      )),
                ],
              ),
            ],
          ),
          
          // Top bar with search
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 12,
                left: 16,
                right: 16,
                bottom: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.menu, color: AppTheme.textPrimary, size: 24),
                      onPressed: () {},
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        print('🏠 HOME SCREEN: Navigating to /destination-search');
                        Navigator.pushNamed(context, '/destination-search');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              color: AppTheme.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Where to?',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedIndex = 2);
                    },
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.surfaceColor,
                      child: Icon(Icons.person, color: AppTheme.textSecondary, size: 24),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Live car count badge
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.successColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_nearbyCarCount cars nearby',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom sheet with content
          DraggableScrollableSheet(
            initialChildSize: 0.50,
            minChildSize: 0.50,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.borderColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Promo Banner Carousel
                    SizedBox(
                      height: 120,
                      child: PageView.builder(
                        controller: _promoController,
                        itemCount: _promos.length,
                        onPageChanged: (page) => setState(() => _currentPromoPage = page),
                        itemBuilder: (context, index) {
                          final promo = _promos[index];
                          return _buildPromoCard(promo);
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Promo dots indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_promos.length, (index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPromoPage == index ? 20 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPromoPage == index
                                ? AppTheme.accentColor
                                : AppTheme.borderColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Quick Actions
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildQuickAction(Icons.directions_car, 'Ride', true),
                          _buildQuickAction(Icons.schedule, 'Schedule', false),
                          _buildQuickAction(Icons.access_time, 'Rentals', false),
                          _buildQuickAction(Icons.local_shipping, 'Delivery', false),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Contextual Suggestion
                    if (_shouldShowWorkSuggestion()) ...[
                      _buildWorkSuggestion(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Saved Places
                    Text(
                      'SAVED PLACES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    _buildSavedPlaceRow(
                      icon: Icons.home_outlined,
                      iconColor: AppTheme.accentColor,
                      title: 'Home',
                      subtitle: 'Add home',
                      fare: '~£12',
                      onTap: () {},
                    ),
                    
                    const SizedBox(height: 12),
                    
                    Divider(color: AppTheme.borderColor, height: 1),
                    
                    const SizedBox(height: 12),
                    
                    _buildSavedPlaceRow(
                      icon: Icons.work_outline,
                      iconColor: AppTheme.primaryColor,
                      title: 'Work',
                      subtitle: 'Add work',
                      fare: '~£15',
                      onTap: () {},
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Recent
                    Text(
                      'RECENT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    ..._recentPlaces.map((place) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildRecentPlaceRow(
                        emoji: place['icon']!,
                        name: place['name']!,
                        address: place['address']!,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/vehicle-selection',
                            arguments: {'destination': place['name']},
                          );
                        },
                      ),
                    )),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
  
  Widget _buildPromoCard(Map<String, dynamic> promo) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: promo['color'],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              promo['icon'],
              color: promo['iconColor'],
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  promo['title'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  promo['subtitle'],
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: promo['iconColor'],
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              promo['cta'],
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildQuickAction(IconData icon, String label, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentColor : AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildWorkSuggestion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.accentColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.work,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Heading to work?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Estimated £15 • 8 min away',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Book'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSavedPlaceRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String fare,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              fare,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
  
  Widget _buildRecentPlaceRow({
    required String emoji,
    required String name,
    required String address,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Rebook',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
