import 'package:flutter/material.dart';
import 'package:skyline/features/home/home_screen.dart';
import 'package:skyline/core/api_service.dart';
import 'package:skyline/core/widgets/custom_snackbar.dart';

class UserRegistrationScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isNewUser;
  final String? name;

  const UserRegistrationScreen({
    super.key, 
    required this.phoneNumber,
    this.isNewUser = false,
    this.name,
  });

  @override
  State<UserRegistrationScreen> createState() => _UserRegistrationScreenState();
}

class _UserRegistrationScreenState extends State<UserRegistrationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _completeRegistration() async {
    if (_otpController.text.length != 6) {
      CustomSnackbar.show(
        context,
        message: 'Please enter a valid 6-digit OTP',
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Use the name passed from previous screen if new user, otherwise null (backend handles it)
      final response = await _apiService.verifyOtp(
        phone: widget.phoneNumber,
        otp: _otpController.text,
        role: 'user',
        name: widget.name, 
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response['success'] == true) {
        CustomSnackbar.show(
          context,
          message: 'Login Successful!',
          type: SnackbarType.success,
        );
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      } else {
        CustomSnackbar.show(
          context,
          message: response['message'] ?? 'Login Failed',
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
        title: const Text('Verify OTP'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verifying ${widget.phoneNumber}',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            
            // Show greeting if name is available
            if (widget.name != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Text(
                  widget.isNewUser 
                    ? 'Welcome, ${widget.name}!' 
                    : 'Welcome back, ${widget.name}!',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

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
            
            // Removed Name Input Section
            
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
                      'Verify & Login',
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
