import 'package:flutter/material.dart';
import '../../core/theme.dart';

class DestinationSearchScreen extends StatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  State<DestinationSearchScreen> createState() => _DestinationSearchScreenState();
}

class _DestinationSearchScreenState extends State<DestinationSearchScreen> {
  final TextEditingController _pickupController = TextEditingController(text: 'Current Location');
  final TextEditingController _destinationController = TextEditingController();
  
  // Mock suggestions
  final List<Map<String, String>> _suggestions = [
    {'name': 'Heathrow Airport', 'address': 'Longford, Hounslow'},
    {'name': 'The Shard', 'address': '32 London Bridge St, London'},
    {'name': 'Buckingham Palace', 'address': 'London SW1A 1AA'},
    {'name': 'Tower Bridge', 'address': 'Tower Bridge Rd, London'},
    {'name': 'Hyde Park', 'address': 'London'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button and fields
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Plan your ride',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildLocationField(
                    context,
                    controller: _pickupController,
                    icon: Icons.my_location,
                    hint: 'Pickup location',
                    isPickup: true,
                  ),
                  const SizedBox(height: 12),
                  _buildLocationField(
                    context,
                    controller: _destinationController,
                    icon: Icons.location_on,
                    hint: 'Where to?',
                    isPickup: false,
                    autofocus: true,
                  ),
                ],
              ),
            ),
            // Suggestions List
            Expanded(
              child: ListView.separated(
                itemCount: _suggestions.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _suggestions[index];
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on, size: 20, color: Colors.grey),
                    ),
                    title: Text(
                      item['name']!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(item['address']!),
                    onTap: () {
                      // Navigate to Vehicle Selection (which is technically part of Home/Map flow usually, 
                      // but for this mockup we can push a new screen or return result)
                      // Let's push a "Booking Screen" which is the map with the bottom sheet for vehicles
                      Navigator.pushNamed(
                        context, 
                        '/vehicle-selection',
                        arguments: {'destination': item},
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationField(
    BuildContext context, {
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    required bool isPickup,
    bool autofocus = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        decoration: InputDecoration(
          prefixIcon: Icon(
            icon,
            color: isPickup ? Colors.blue : Theme.of(context).primaryColor,
            size: 20,
          ),
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
