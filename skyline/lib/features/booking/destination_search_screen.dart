import 'package:flutter/material.dart';
import '../../core/theme.dart';

class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  State<DestinationSearchScreen> createState() => _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  
  List<Map<String, String>> _suggestions = [];
  
  final List<Map<String, String>> _savedPlaces = [
    {'icon': '🏠', 'title': 'Home', 'subtitle': 'Add home', 'type': 'add'},
    {'icon': '💼', 'title': 'Work', 'subtitle': 'Add work', 'type': 'add'},
  ];
  
  final List<Map<String, String>> _recentPlaces = [
    {'icon': '✈️', 'name': 'Heathrow Terminal 5', 'address': 'Longford TW6, UK', 'distance': '15 mi'},
    {'icon': '🏢', 'name': 'The Shard', 'address': 'London Bridge, SE1', 'distance': '2 mi'},
    {'icon': '🚉', 'name': 'King\'s Cross Station', 'address': 'Kings Cross, N1', 'distance': '3 mi'},
  ];
  
  final List<Map<String, String>> _allDestinations = [
    {'icon': '✈️', 'name': 'Heathrow Terminal 5', 'address': 'Longford TW6, UK', 'distance': '15 mi'},
    {'icon': '✈️', 'name': 'Heathrow Terminal 2', 'address': 'Longford TW6, UK', 'distance': '14 mi'},
    {'icon': '🏢', 'name': 'The Shard', 'address': 'London Bridge, SE1', 'distance': '2 mi'},
    {'icon': '🏛️', 'name': 'British Museum', 'address': 'Great Russell St, WC1B', 'distance': '1 mi'},
    {'icon': '🚉', 'name': 'King\'s Cross Station', 'address': 'Kings Cross, N1', 'distance': '3 mi'},
    {'icon': '👑', 'name': 'Buckingham Palace', 'address': 'Westminster, SW1A', 'distance': '4 mi'},
  ];

  @override
  void initState() {
    super.initState();
    print('🔍 DESTINATION SEARCH: Screen loaded');
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
    
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    
    setState(() {
      _suggestions = _allDestinations
          .where((place) =>
              place['name']!.toLowerCase().contains(query) ||
              place['address']!.toLowerCase().contains(query))
          .toList();
    });
  }

  void _selectDestination(String name, String address) {
    print('🔍 DESTINATION SEARCH: Selected "$name"');
    print('🔍 DESTINATION SEARCH: Navigating to /vehicle-selection');
    Navigator.pushReplacementNamed(
      context,
      '/vehicle-selection',
      arguments: {'destination': name, 'address': address},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with back and current location
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                    color: AppTheme.textPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Where to?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.my_location),
                    onPressed: () {},
                    color: AppTheme.accentColor,
                  ),
                ],
              ),
            ),
            
            // Search input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Search destination',
                    border: InputBorder.none,
                    icon: Icon(Icons.search, color: AppTheme.textSecondary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: AppTheme.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _suggestions = []);
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Content
            Expanded(
              child: _suggestions.isNotEmpty
                  ? _buildSearchResults()
                  : _buildDefaultContent(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSearchResults() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _suggestions.length,
      separatorBuilder: (context, index) => Divider(
        color: AppTheme.borderColor,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final place = _suggestions[index];
        return _buildDestinationRow(
          icon: place['icon']!,
          name: place['name']!,
          address: place['address']!,
          distance: place['distance']!,
          onTap: () => _selectDestination(place['name']!, place['address']!),
        );
      },
    );
  }
  
  Widget _buildDefaultContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
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
        
        ..._savedPlaces.map((place) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildSavedPlaceRow(
            icon: place['icon']!,
            title: place['title']!,
            subtitle: place['subtitle']!,
            onTap: () {
              // TODO: Add saved place
            },
          ),
        )),
        
        const SizedBox(height: 24),
        
        Divider(color: AppTheme.borderColor, height: 1),
        
        const SizedBox(height: 24),
        
        // Recent Places
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
          child: _buildDestinationRow(
            icon: place['icon']!,
            name: place['name']!,
            address: place['address']!,
            distance: place['distance']!,
            onTap: () => _selectDestination(place['name']!, place['address']!),
          ),
        )),
      ],
    );
  }
  
  Widget _buildSavedPlaceRow({
    required String icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 22)),
              ),
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
            Icon(Icons.add, color: AppTheme.accentColor, size: 20),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDestinationRow({
    required String icon,
    required String name,
    required String address,
    required String distance,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 22)),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              distance,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
