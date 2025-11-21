import 'package:flutter/material.dart';
import 'package:skyline/features/auth/user_registration_screen.dart';
import 'package:skyline/features/auth/driver_registration_screen.dart';
import 'package:skyline/core/api_service.dart';

class PhoneLoginScreen extends StatefulWidget {
  final String role; // 'user' or 'driver'

  const PhoneLoginScreen({super.key, required this.role});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String _selectedCountryCode = '+91';
  final List<String> _countryCodes = ['+91', '+1', '+44', '+971'];
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _onContinue() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });

    final fullPhoneNumber = '$_selectedCountryCode$phone';
    debugPrint('📱 ------------------------------------------------------------------');
    debugPrint('📱 [PhoneLoginScreen] User tapped Continue');
    debugPrint('📱 [PhoneLoginScreen] Phone: $fullPhoneNumber');
    debugPrint('📱 [PhoneLoginScreen] Role: ${widget.role}');

    try {
      debugPrint('⏳ [PhoneLoginScreen] Calling ApiService.sendOtp...');
      final response = await _apiService.sendOtp(fullPhoneNumber);
      debugPrint('✅ [PhoneLoginScreen] API Call Completed');
      
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (response['success'] == true) {
        final otp = response['data']['otp']; // Extract OTP for testing/autofill if needed
        debugPrint('🎉 [PhoneLoginScreen] OTP Sent Successfully. OTP: $otp');
        
        // Show OTP in snackbar for testing convenience
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OTP Sent: $otp')),
        );

        debugPrint('🚀 [PhoneLoginScreen] Navigating to Registration Screen...');
        debugPrint('📱 ------------------------------------------------------------------');

        if (widget.role == 'user') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserRegistrationScreen(phoneNumber: fullPhoneNumber),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DriverRegistrationScreen(phoneNumber: fullPhoneNumber),
            ),
          );
        }
      } else {
        debugPrint('⚠️ [PhoneLoginScreen] API returned success=false. Message: ${response['message']}');
        debugPrint('📱 ------------------------------------------------------------------');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Failed to send OTP')),
        );
      }
    } catch (e) {
      debugPrint('❌ [PhoneLoginScreen] Error occurred: $e');
      debugPrint('📱 ------------------------------------------------------------------');
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
        title: Text('Login as ${widget.role == 'user' ? 'User' : 'Driver'}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your mobile number',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'We will send you a confirmation code',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCountryCode,
                      items: _countryCodes.map((String code) {
                        return DropdownMenuItem<String>(
                          value: code,
                          child: Text(code),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedCountryCode = newValue!;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
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
