import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/models/airport.dart';
import '../../core/services/airport_service.dart';
import '../../core/services/location_cache_service.dart';
import '../../core/services/places_service.dart';
import '../../core/services/geocoding_service.dart';
import '../booking/widgets/vehicle_selection_widget.dart';
import '../booking/widgets/schedule_ride_sheet.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';

class AirportSelectionScreen extends StatefulWidget {
  const AirportSelectionScreen({super.key});

  @override
  State<AirportSelectionScreen> createState() => _AirportSelectionScreenState();
}

class _AirportSelectionScreenState extends State<AirportSelectionScreen> {
  final AirportService _airportService = AirportService();

  List<Airport> _airports = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAirports();
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

  void _selectAirport(Airport airport) {
    // Navigate to vehicle selection screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _AirportVehicleSelectionScreen(airport: airport),
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
                  const Icon(Icons.error_outline, size: 64, color: Colors.grey),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen for vehicle selection with airport as destination
class _AirportVehicleSelectionScreen extends StatefulWidget {
  final Airport airport;

  const _AirportVehicleSelectionScreen({required this.airport});

  @override
  State<_AirportVehicleSelectionScreen> createState() =>
      _AirportVehicleSelectionScreenState();
}

class _AirportVehicleSelectionScreenState
    extends State<_AirportVehicleSelectionScreen> {
  final LocationCacheService _locationCache = LocationCacheService();
  final PlacesService _placesService = PlacesService();
  final GeocodingService _geocodingService = GeocodingService();

  latlong.LatLng? _pickupLocation;
  String _pickupAddress = '';
  bool _isLocationReady = false;
  bool _isLocationLoading = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    debugPrint('📍 AirportVehicleSelection: Fetching location');
    if (!mounted) return;

    setState(() {
      _isLocationLoading = true;
    });

    // Try cached location first
    final cachedPosition = _locationCache.cachedPosition;
    if (cachedPosition != null) {
      debugPrint('📍 AirportVehicleSelection: Using cached location');
      await _processLocation(cachedPosition);
      return;
    }

    // Fetch fresh location
    try {
      final position = await _locationCache.getLocation();
      if (position != null) {
        await _processLocation(position);
      } else {
        debugPrint('📍 AirportVehicleSelection: Failed to get location');
        if (mounted) {
          setState(() {
            _isLocationLoading = false;
            _isLocationReady = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Unable to get your location'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: _getCurrentLocation,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('📍 AirportVehicleSelection: Error: $e');
      if (mounted) {
        setState(() {
          _isLocationLoading = false;
          _isLocationReady = false;
        });
      }
    }
  }

  Future<void> _processLocation(Position position) async {
    debugPrint(
      '📍 AirportVehicleSelection: Processing ${position.latitude}, ${position.longitude}',
    );
    if (!mounted) return;

    setState(() {
      _pickupLocation = latlong.LatLng(position.latitude, position.longitude);
    });

    // Reverse geocode to get address - same as destination_search_screen
    try {
      // Try backend API first
      String? address = await _placesService.getAddressFromLatLng(
        position.latitude,
        position.longitude,
      );

      // If backend fails, try Nominatim (OpenStreetMap) as fallback
      if (address == null || address.isEmpty) {
        debugPrint(
          '📍 AirportVehicleSelection: Backend geocoding failed, trying Nominatim...',
        );
        address = await _geocodingService.getAddressFromLatLng(
          position.latitude,
          position.longitude,
        );
      }

      if (address != null && address.isNotEmpty && mounted) {
        setState(() {
          // Store the full address for the API
          _pickupAddress = address!;
          _isLocationReady = true;
          _isLocationLoading = false;
        });
        debugPrint(
          '📍 AirportVehicleSelection: Geocoded location to: $address',
        );
      } else if (mounted) {
        debugPrint('⚠️ AirportVehicleSelection: All geocoding methods failed');
        // Use coordinates as fallback but mark as ready
        setState(() {
          _pickupAddress =
              "Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}";
          _isLocationReady = true;
          _isLocationLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ AirportVehicleSelection: Error reverse geocoding: $e");
      if (mounted) {
        setState(() {
          _pickupAddress =
              "Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}";
          _isLocationReady = true;
          _isLocationLoading = false;
        });
      }
    }
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
          'Select Vehicle',
          style: GoogleFonts.outfit(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Location loading banner
          if (_isLocationLoading)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue[50],
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Getting your location...',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            )
          else if (!_isLocationReady)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange[50],
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orange[900],
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Unable to get location',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _getCurrentLocation,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),

          // Route info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                _buildLocationRow(
                  icon: Icons.my_location,
                  color: Colors.green,
                  label: 'Pickup',
                  address: _isLocationLoading
                      ? 'Fetching location...'
                      : _pickupAddress.isNotEmpty
                      ? _pickupAddress
                      : 'Location unavailable',
                ),
                const SizedBox(height: 12),
                _buildLocationRow(
                  icon: Icons.flight,
                  color: Colors.blue,
                  label: 'Airport',
                  address: widget.airport.name,
                ),
              ],
            ),
          ),

          // Vehicle selection
          Expanded(
            child: _isLocationReady && _pickupLocation != null
                ? VehicleSelectionWidget(
                    onVehicleSelected: (categorySlug) {},
                    onSelectVehicle: (categorySlug, categoryName, fareData) {
                      _handleVehicleSelection(
                        categorySlug,
                        categoryName,
                        fareData,
                      );
                    },
                    onPrebookVehicle: (categorySlug, categoryName, fareData) {
                      _handlePrebookVehicleSelection(
                        categorySlug,
                        categoryName,
                        fareData,
                      );
                    },
                    pickupLat: _pickupLocation!.latitude,
                    pickupLng: _pickupLocation!.longitude,
                    dropoffLat: widget.airport.coordinates.lat,
                    dropoffLng: widget.airport.coordinates.lng,
                    fixedFareByCategory: widget.airport.pricing,
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isLocationLoading)
                          const CircularProgressIndicator()
                        else
                          const Icon(
                            Icons.location_off,
                            size: 64,
                            color: Colors.grey,
                          ),
                        const SizedBox(height: 16),
                        Text(
                          _isLocationLoading
                              ? 'Getting your location...'
                              : 'Location required to show vehicles',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (!_isLocationLoading && !_isLocationReady)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: ElevatedButton(
                              onPressed: _getCurrentLocation,
                              child: const Text('Retry'),
                            ),
                          ),
                      ],
                    ),
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
    String categorySlug,
    String categoryName,
    Map<String, dynamic> fareData,
  ) async {
    if (_pickupLocation == null || !_isLocationReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for location to be ready'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Create location maps with placeId for airport detection
    final pickupLocationMap = {
      'coordinates': [_pickupLocation!.longitude, _pickupLocation!.latitude],
      'address': _pickupAddress,
    };

    final dropoffLocationMap = {
      'coordinates': [
        widget.airport.coordinates.lng,
        widget.airport.coordinates.lat,
      ],
      'address': widget.airport.address,
      'placeId':
          widget.airport.placeId, // Include placeId for airport detection
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

  void _handlePrebookVehicleSelection(
    String categorySlug,
    String categoryName,
    Map<String, dynamic> fareData,
  ) async {
    if (_pickupLocation == null || !_isLocationReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for location to be ready'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Create location maps with placeId for airport detection
    final pickupLocationMap = {
      'coordinates': [_pickupLocation!.longitude, _pickupLocation!.latitude],
      'address': _pickupAddress,
    };

    final dropoffLocationMap = {
      'coordinates': [
        widget.airport.coordinates.lng,
        widget.airport.coordinates.lat,
      ],
      'address': widget.airport.address,
      'placeId':
          widget.airport.placeId, // Include placeId for airport detection
    };

    // Show the schedule sheet FIRST (before navigating to RideConfirmationScreen)
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduleRideSheet(
        initialDateTime: DateTime.now().add(const Duration(minutes: 30)),
        onSchedule: (selectedDateTime, notes) async {
          // User selected a time, now navigate to RideConfirmationScreen with the scheduled time
          if (!mounted) return;

          debugPrint(
            '📅 AirportSelectionScreen: Prebook scheduled for: $selectedDateTime',
          );

          // Navigate to ride confirmation with scheduledDateTime
          final result = await Navigator.pushNamed(
            context,
            '/ride-confirmation',
            arguments: {
              'pickupLocation': pickupLocationMap,
              'dropoffLocation': dropoffLocationMap,
              'categorySlug': categorySlug,
              'categoryName': categoryName,
              'fareData': fareData,
              'isScheduled': true, // Mark as scheduled
              'scheduledDateTime': selectedDateTime, // Pass the selected time
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
        },
      ),
    );
  }
}

