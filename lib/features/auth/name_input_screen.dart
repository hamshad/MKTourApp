import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mktours/features/auth/user_registration_screen.dart';

import '../../core/api_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/custom_snackbar.dart';
import 'driver_registration_screen.dart';


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

        // Navigate based on role
        if (widget.role == 'driver') {
          // For drivers, we navigate to DriverRegistrationScreen
          // Note: DriverRegistrationScreen might need to be updated to accept name if it's not already
          // But based on previous code, it seems to ask for name again or we can pass it.
          // Let's check DriverRegistrationScreen. It asks for name. 
          // We can either pass it or let them enter it again. 
          // Ideally, we should pass it. 
          // For now, let's navigate to DriverRegistrationScreen. 
          // Since DriverRegistrationScreen takes phoneNumber, we pass that.
          // We might need to refactor DriverRegistrationScreen to accept name as well to pre-fill it.
          // But for now, let's just navigate there.
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DriverRegistrationScreen(
                phoneNumber: widget.phoneNumber,
              ),
            ),
          );
        } else {
          // For users, navigate to UserRegistrationScreen
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
        }
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What should we call you?',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please enter your full name to create an account.',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 40),
              
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _nameController,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Full Name',
                    hintStyle: GoogleFonts.outfit(color: AppTheme.textSecondary),
                    border: InputBorder.none,
                    icon: const Icon(Icons.person_outline, color: AppTheme.textSecondary),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              
              const Spacer(),
              
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
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
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
