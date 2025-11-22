import 'package:flutter/material.dart';
import 'package:skyline/core/api_service.dart';
import 'package:skyline/features/driver/driver_home_screen.dart';
import 'package:skyline/core/widgets/custom_snackbar.dart';

class DriverRegistrationScreen extends StatefulWidget {
  final String phoneNumber;

  const DriverRegistrationScreen({super.key, required this.phoneNumber});

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  // final TextEditingController _licenseController = TextEditingController(); // Removed as per JSON requirement
  // final TextEditingController _vehicleTypeController = TextEditingController(); // Replaced by dropdown
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _vehicleColorController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  
  String? _selectedVehicleType;
  final List<String> _vehicleTypes = ['sedan', 'suv', 'hatchback', 'van'];

  String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);

  Future<void> _completeRegistration() async {
    if (_otpController.text.length != 6) {
      CustomSnackbar.show(
        context,
        message: 'Please enter a valid 6-digit OTP',
        type: SnackbarType.warning,
      );
      return;
    }

    if (_nameController.text.isEmpty || 
        _selectedVehicleType == null || 
        _vehicleModelController.text.isEmpty || 
        _vehicleNumberController.text.isEmpty || 
        _vehicleColorController.text.isEmpty) {
      CustomSnackbar.show(
        context,
        message: 'Please fill all fields',
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final vehicleDetails = {
        "type": _selectedVehicleType,
        "model": _vehicleModelController.text,
        "number": _vehicleNumberController.text,
        "color": _vehicleColorController.text
      };

      final response = await _apiService.verifyOtp(
        phone: widget.phoneNumber,
        otp: _otpController.text,
        role: 'driver',
        name: _nameController.text,
        vehicleDetails: vehicleDetails,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response['success'] == true) {
        CustomSnackbar.show(
          context,
          message: 'Registration Successful!',
          type: SnackbarType.success,
        );
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const DriverHomeScreen()),
          (route) => false,
        );
      } else {
        CustomSnackbar.show(
          context,
          message: response['message'] ?? 'Registration Failed',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Verification'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verifying ${widget.phoneNumber}',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Verification'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter OTP',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        hintText: 'XXXXXX',
                        border: OutlineInputBorder(),
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Personal Details'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Vehicle Information'),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedVehicleType,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                      items: _vehicleTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(_capitalize(type)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedVehicleType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _vehicleModelController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Model (e.g., Toyota Camry)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.model_training),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _vehicleNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Number (e.g., ABC-1234)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.pin_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _vehicleColorController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Color (e.g., Silver)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.color_lens_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _completeRegistration,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 4,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Submit for Approval',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}
