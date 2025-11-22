import 'package:flutter/material.dart';
import 'package:skyline/core/api_service.dart';
import 'package:skyline/features/auth/user_registration_screen.dart';
import 'package:skyline/core/widgets/custom_snackbar.dart';

class NameInputScreen extends StatefulWidget {
  final String phoneNumber;
  final String role;

  const NameInputScreen({
    super.key,
    required this.phoneNumber,
    required this.role,
  });

  @override
  State<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends State<NameInputScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _onContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      CustomSnackbar.show(
        context,
        message: 'Please enter your name',
        type: SnackbarType.warning,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Send OTP before navigating
      debugPrint('⏳ [NameInputScreen] Calling ApiService.sendOtp...');
      final response = await _apiService.sendOtp(widget.phoneNumber);
      
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response['success'] == true) {
        final otp = response['data']['otp'];
        debugPrint('🎉 [NameInputScreen] OTP Sent. OTP: $otp');
        
        CustomSnackbar.show(
          context,
          message: 'OTP Sent: $otp',
          type: SnackbarType.success,
        );

        // Navigate to OTP Screen (UserRegistrationScreen refactored)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserRegistrationScreen(
              phoneNumber: widget.phoneNumber,
              isNewUser: true,
              name: name,
            ),
          ),
        );
      } else {
        CustomSnackbar.show(
          context,
          message: response['message'] ?? 'Failed to send OTP',
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
        title: const Text('Enter Your Name'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'What should we call you?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please enter your full name to create an account.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _onContinue,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Continue',
                      style: TextStyle(fontSize: 18),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
