import 'package:flutter/material.dart';
import 'package:skyline/features/home/home_screen.dart';
import 'package:skyline/core/api_service.dart'; // Assuming this exists or will exist

class UserRegistrationScreen extends StatefulWidget {
  final String phoneNumber;

  const UserRegistrationScreen({super.key, required this.phoneNumber});

  @override
  State<UserRegistrationScreen> createState() => _UserRegistrationScreenState();
}

class _UserRegistrationScreenState extends State<UserRegistrationScreen> {
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _completeRegistration() async {
    if (_otpController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit OTP')),
      );
      return;
    }

    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _apiService.verifyOtp(
        phone: widget.phoneNumber,
        otp: _otpController.text,
        role: 'user',
        name: _nameController.text,
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration Successful!')),
        );
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Registration Failed')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Verification'),
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
                      'Start Riding',
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
