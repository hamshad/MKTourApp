import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../driver/driver_home_screen.dart';

class DriverRegistrationScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isNewUser;
  final String? name;

  const DriverRegistrationScreen({
    super.key, 
    required this.phoneNumber,
    this.isNewUser = true,
    this.name,
  });

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _vehicleColorController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  
  String? _selectedVehicleType;
  final List<String> _vehicleTypes = ['sedan', 'suv', 'hatchback', 'van'];

  @override
  void initState() {
    super.initState();
    if (widget.name != null) {
      _nameController.text = widget.name!;
    }
  }

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

    // Only validate registration fields if it's a new user
    if (widget.isNewUser) {
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
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Map<String, dynamic>? vehicleDetails;
      
      if (widget.isNewUser) {
        vehicleDetails = {
          "type": _selectedVehicleType,
          "model": _vehicleModelController.text,
          "number": _vehicleNumberController.text,
          "color": _vehicleColorController.text
        };
      }

      final response = await _apiService.verifyOtp(
        phone: widget.phoneNumber,
        otp: _otpController.text,
        role: 'driver',
        name: widget.isNewUser ? _nameController.text : null,
        vehicleDetails: vehicleDetails,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response['success'] == true) {
        CustomSnackbar.show(
          context,
          message: widget.isNewUser ? 'Registration Successful!' : 'Login Successful!',
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
          message: response['message'] ?? 'Verification Failed',
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isNewUser ? 'Driver Registration' : 'Driver Login',
          style: GoogleFonts.outfit(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // OTP Section
            _buildSectionHeader('Verification'),
            const SizedBox(height: 8),
            Text(
              'Enter the code sent to ${widget.phoneNumber}',
              style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 8,
                ),
                decoration: const InputDecoration(
                  hintText: '000000',
                  border: InputBorder.none,
                  counterText: '',
                  hintStyle: TextStyle(color: Colors.grey, letterSpacing: 8),
                ),
                textAlign: TextAlign.center,
              ),
            ),

            if (widget.isNewUser) ...[
              const SizedBox(height: 32),
              
              // Personal Details
              _buildSectionHeader('Personal Details'),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 32),

              // Vehicle Details
              _buildSectionHeader('Vehicle Information'),
              const SizedBox(height: 16),
              
              // Vehicle Type Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedVehicleType,
                    isExpanded: true,
                    hint: Row(
                      children: [
                        const Icon(Icons.directions_car_outlined, color: AppTheme.textSecondary),
                        const SizedBox(width: 12),
                        Text(
                          'Select Vehicle Type',
                          style: GoogleFonts.outfit(color: AppTheme.textSecondary, fontSize: 16),
                        ),
                      ],
                    ),
                    items: _vehicleTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car_outlined, color: AppTheme.textPrimary),
                            const SizedBox(width: 12),
                            Text(
                              _capitalize(type),
                              style: GoogleFonts.outfit(color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedVehicleType = value),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              _buildTextField(
                controller: _vehicleModelController,
                label: 'Vehicle Model (e.g., Toyota Camry)',
                icon: Icons.model_training,
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _vehicleNumberController,
                      label: 'Vehicle Number',
                      icon: Icons.pin_outlined,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _vehicleColorController,
                      label: 'Color',
                      icon: Icons.color_lens_outlined,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 40),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _completeRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text(
                        widget.isNewUser ? 'Submit Application' : 'Verify & Login',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.outfit(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
