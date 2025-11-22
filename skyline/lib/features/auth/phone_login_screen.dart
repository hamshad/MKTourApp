import 'package:flutter/material.dart';
import 'package:skyline/features/auth/user_registration_screen.dart';
import 'package:skyline/features/auth/driver_registration_screen.dart';
import 'package:skyline/features/auth/name_input_screen.dart';
import 'package:skyline/core/api_service.dart';
import 'package:skyline/core/widgets/custom_snackbar.dart';

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
      CustomSnackbar.show(
        context,
        message: 'Please enter your phone number',
        type: SnackbarType.warning,
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
      // Step 1: Check Phone
      debugPrint('⏳ [PhoneLoginScreen] Calling ApiService.checkPhone...');
      final checkResponse = await _apiService.checkPhone(fullPhoneNumber, widget.role);
      
      if (!mounted) return;

      if (checkResponse['success'] == true) {
        final data = checkResponse['data'];
        final bool isNewUser = data['isNewUser'] ?? false;
        final String? existingName = data['user']?['name'];

        debugPrint('🔍 [PhoneLoginScreen] Check Phone Result: isNewUser=$isNewUser, Name=$existingName');

        if (isNewUser) {
          // Case A: New User -> Go to Name Input Screen
          debugPrint('🆕 [PhoneLoginScreen] New User detected. Navigating to NameInputScreen...');
          setState(() {
            _isLoading = false;
          });
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NameInputScreen(
                phoneNumber: fullPhoneNumber,
                role: widget.role,
              ),
            ),
          );
        } else {
          // Case B: Returning User -> Show Welcome & Send OTP
          debugPrint('👋 [PhoneLoginScreen] Returning User detected. Sending OTP...');
          
          if (existingName != null) {
            CustomSnackbar.show(
              context,
              message: 'Welcome back, $existingName! Sending OTP...',
              type: SnackbarType.info,
            );
          }

          // Send OTP
          final otpResponse = await _apiService.sendOtp(fullPhoneNumber);
          
          if (!mounted) return;
          
          setState(() {
            _isLoading = false;
          });

          if (otpResponse['success'] == true) {
            final otp = otpResponse['data']['otp'];
            debugPrint('🎉 [PhoneLoginScreen] OTP Sent. OTP: $otp');
            CustomSnackbar.show(
              context,
              message: 'OTP Sent: $otp',
              type: SnackbarType.success,
            );

            // Navigate to OTP Screen (UserRegistrationScreen)
            // Pass isNewUser=false and name=null (or existing name if we want to display it, but logic says skip input)
             if (widget.role == 'user') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserRegistrationScreen(
                    phoneNumber: fullPhoneNumber,
                    isNewUser: false,
                    name: existingName,
                  ),
                ),
              );
            } else {
              // For drivers, we might keep the old flow or update similarly
              // Assuming driver flow is similar for now, or keeping as is
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DriverRegistrationScreen(phoneNumber: fullPhoneNumber),
                ),
              );
            }
          } else {
             CustomSnackbar.show(
               context,
               message: otpResponse['message'] ?? 'Failed to send OTP',
               type: SnackbarType.error,
             );
          }
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        CustomSnackbar.show(
          context,
          message: checkResponse['message'] ?? 'Failed to check phone',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      debugPrint('❌ [PhoneLoginScreen] Error occurred: $e');
      debugPrint('📱 ------------------------------------------------------------------');
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
