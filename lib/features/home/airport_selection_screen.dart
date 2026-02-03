import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/models/airport.dart';
import '../../core/services/airport_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/places_service.dart';
import '../booking/widgets/vehicle_selection_widget.dart';
import 'package:latlong2/latlong.dart' as latlong;

class AirportSelectionScreen extends StatefulWidget {
  const AirportSelectionScreen({super.key});

  @override
  State<AirportSelectionScreen> createState() => _AirportSelectionScreenState();
}

class _AirportSelectionScreenState extends State<AirportSelectionScreen> {
  final AirportService _airportService = AirportService();
  final LocationService _locationService = LocationService();
  final PlacesService _placesService = PlacesService();

  List<Airport> _airports = [];
  bool _isLoading = true;
  String? _errorMessage;

  latlong.LatLng? _currentLocation;
  String _currentAddress = 'Current Location';

  @override
  void initState() {
    super.initState();
    _loadAirports();
    _getCurrentLocation();
  }

  Future<void> _loadAirports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final airports = await _airportService.getActiveAirports();
      if (mounted) {
        setState(() {
          _airports = airports;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load airports. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    final position = await _locationService.getCurrentLocation();
    if (position != null && mounted) {
      setState(() {
        _currentLocation = latlong.LatLng(position.latitude, position.longitude);
      });

      // Fetch address
      final address = await _placesService.getAddressFromLatLng(
        position.latitude,
        position.longitude,
      );
      if (address != null && mounted) {
        setState(() {
          _currentAddress = address;
        });
      }
    }
  }

  void _selectAirport(Airport airport) {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Getting your location...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Navigate to vehicle selection with pickup as current location and dropoff as airport
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _AirportVehicleSelectionScreen(
          airport: airport,
          pickupLocation: _currentLocation!,
          pickupAddress: _currentAddress,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Airport',
          style: GoogleFonts.outfit(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadAirports,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _airports.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.flight_takeoff,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No airports available',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _airports.length,
                      itemBuilder: (context, index) {
                        final airport = _airports[index];
                        return _buildAirportCard(airport);
                      },
                    ),
    );
  }

  Widget _buildAirportCard(Airport airport) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _selectAirport(airport),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.flight,
                  size: 28,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      airport.name,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      airport.address,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen for vehicle selection with airport as destination
class _AirportVehicleSelectionScreen extends StatelessWidget {
  final Airport airport;
  final latlong.LatLng pickupLocation;
  final String pickupAddress;

  const _AirportVehicleSelectionScreen({
    required this.airport,
    required this.pickupLocation,
    required this.pickupAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Vehicle',
          style: GoogleFonts.outfit(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Route info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Column(
              children: [
                _buildLocationRow(
                  icon: Icons.my_location,
                  color: Colors.green,
                  label: 'Pickup',
                  address: pickupAddress,
                ),
                const SizedBox(height: 12),
                _buildLocationRow(
                  icon: Icons.flight,
                  color: Colors.blue,
                  label: 'Airport',
                  address: airport.name,
                ),
              ],
            ),
          ),

          // Vehicle selection
          Expanded(
            child: VehicleSelectionWidget(
              onVehicleSelected: (categorySlug) {},
              onSelectVehicle: (categorySlug, categoryName, fareData) {
                _handleVehicleSelection(
                  context,
                  categorySlug,
                  categoryName,
                  fareData,
                );
              },
              pickupLat: pickupLocation.latitude,
              pickupLng: pickupLocation.longitude,
              dropoffLat: airport.coordinates.lat,
              dropoffLng: airport.coordinates.lng,
              fixedFareByCategory: airport.pricing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required Color color,
    required String label,
    required String address,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleVehicleSelection(
    BuildContext context,
    String categorySlug,
    String categoryName,
    Map<String, dynamic> fareData,
  ) async {
    // Create location maps with placeId for airport detection
    final pickupLocationMap = {
      'coordinates': [pickupLocation.longitude, pickupLocation.latitude],
      'address': pickupAddress,
    };

    final dropoffLocationMap = {
      'coordinates': [airport.coordinates.lng, airport.coordinates.lat],
      'address': airport.address,
      'placeId': airport.placeId, // Include placeId for airport detection
    };

    // Navigate to ride confirmation
    final result = await Navigator.pushNamed(
      context,
      '/ride-confirmation',
      arguments: {
        'pickupLocation': pickupLocationMap,
        'dropoffLocation': dropoffLocationMap,
        'categorySlug': categorySlug,
        'categoryName': categoryName,
        'fareData': fareData,
      },
    );

    // If booking was successful, pop back to home screen
    if (result != null && result is Map && result['status'] == 'searching') {
      if (context.mounted) {
        // Pop back to airport selection screen
        Navigator.pop(context);
        // Pop back to home screen with the result
        Navigator.pop(context, result);
      }
    }
  }
}
