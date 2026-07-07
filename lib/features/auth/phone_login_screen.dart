import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mktours/core/constants/api_constants.dart';
import 'package:mktours/features/auth/user_registration_screen.dart';

import '../../core/api_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/custom_snackbar.dart';
import 'driver_registration_screen.dart';

class PhoneLoginScreen extends StatefulWidget {
  final String role;

  const PhoneLoginScreen({super.key, required this.role});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String _selectedCountryCode = '+44';
  final List<String> _countryCodes = ApiConstants.baseUrl.contains('mktours')
      ? ['+91', '+44', '+971']
      : ['+91', '+1', '+44'];
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  Future<void> _sendOtpAndNavigate() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      CustomSnackbar.show(
        context,
        message: 'Please enter your phone number',
        type: SnackbarType.warning,
      );
      return;
    }

    final fullPhoneNumber = '$_selectedCountryCode$phone';
    final email = _emailController.text.trim();
    final method = email.isNotEmpty ? 'email' : 'sms';

    setState(() => _isLoading = true);

    try {
      debugPrint('⏳ [PhoneLoginScreen] Checking phone status...');
      final checkResponse = await _apiService.checkPhone(
        fullPhoneNumber,
        widget.role,
      );

      if (!mounted) return;

      final bool isNewUser = checkResponse['success'] == true
          ? (checkResponse['data']?['isNewUser'] ?? true)
          : true;
      final String? existingName =
          checkResponse['data']?['user']?['name'];

      debugPrint(
          '🔍 [PhoneLoginScreen] isNewUser=$isNewUser, Name=$existingName');

      debugPrint('⏳ [PhoneLoginScreen] Sending OTP via $method...');
      final otpResponse = await _apiService.sendOtp(
        phone: fullPhoneNumber,
        method: method,
        email: email.isNotEmpty ? email : null,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (otpResponse['success'] == true) {
        debugPrint('🎉 [PhoneLoginScreen] OTP Sent');

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => widget.role == 'driver'
                ? DriverRegistrationScreen(
                    phoneNumber: fullPhoneNumber,
                    isNewUser: isNewUser,
                    name: existingName,
                    email: email.isNotEmpty ? email : null,
                  )
                : UserRegistrationScreen(
                    phoneNumber: fullPhoneNumber,
                    isNewUser: isNewUser,
                    name: existingName,
                    email: email.isNotEmpty ? email : null,
                  ),
          ),
        );
      } else {
        CustomSnackbar.show(
          context,
          message: otpResponse['message'] ?? 'Failed to send OTP',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      debugPrint('❌ [PhoneLoginScreen] Error occurred: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      CustomSnackbar.show(
        context,
        message: 'Error: $e',
        type: SnackbarType.error,
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
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
              Navigator.pushReplacementNamed(context, '/role-selection');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: AppTheme.borderColor),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCountryCode,
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: AppTheme.textSecondary,
                          ),
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
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Phone Number',
                          hintStyle: GoogleFonts.outfit(
                            color: AppTheme.textSecondary,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Email Input (for OTP delivery)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Email (for OTP)',
                    hintStyle: GoogleFonts.outfit(
                      color: AppTheme.textSecondary,
                    ),
                    border: InputBorder.none,
                    icon: const Icon(
                      Icons.email_outlined,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'OTP will be sent via email if provided, otherwise via SMS.',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtpAndNavigate,
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
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Continue',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
