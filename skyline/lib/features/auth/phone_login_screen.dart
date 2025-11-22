import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:skyline/features/auth/user_registration_screen.dart';
import 'package:skyline/features/auth/driver_registration_screen.dart';
import 'package:skyline/features/auth/name_input_screen.dart';
import 'package:skyline/core/api_service.dart';
import 'package:skyline/core/widgets/custom_snackbar.dart';
import 'package:skyline/core/theme.dart';

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
            // CustomSnackbar.show(
            //   context,
            //   message: 'Welcome back, $existingName! Sending OTP...',
            //   type: SnackbarType.info,
            // );
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              // If we can't pop (e.g. after sign out), go to RoleSelectionScreen
              Navigator.pushReplacementNamed(context, '/role-selection');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your mobile number',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We need to verify your identity',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 40),
              
              // Phone Input Row
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: Row(
                  children: [
                    // Country Code Dropdown
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: AppTheme.borderColor)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCountryCode,
                          icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textSecondary),
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
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
                    
                    // Phone Number Input
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Phone Number',
                          hintStyle: GoogleFonts.outfit(color: AppTheme.textSecondary),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onContinue,
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
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)
                      )
                    : Text(
                        'Continue',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
