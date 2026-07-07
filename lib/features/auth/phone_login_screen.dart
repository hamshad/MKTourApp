import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mktours/core/constants/countries.dart';
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
  Country _selectedCountry = countries.firstWhere((c) => c.dialCode == '+44');
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

    final fullPhoneNumber = '${_selectedCountry.dialCode}$phone';
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

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        TextEditingController searchController = TextEditingController();
        ValueNotifier<List<Country>> filtered =
            ValueNotifier(List.from(countries));

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search country...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (query) {
                        setModalState(() {
                          filtered.value = countries
                              .where((c) =>
                                  c.name
                                      .toLowerCase()
                                      .contains(query.toLowerCase()) ||
                                  c.dialCode.contains(query))
                              .toList();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ValueListenableBuilder<List<Country>>(
                      valueListenable: filtered,
                      builder: (context, list, _) {
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = list[index];
                            return ListTile(
                              leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                              title: Text(
                                c.name,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: Text(
                                c.dialCode,
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              onTap: () {
                                setState(() => _selectedCountry = c);
                                Navigator.pop(context);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
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
                      child: InkWell(
                        onTap: _showCountryPicker,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedCountry.flag,
                                style: const TextStyle(fontSize: 22),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _selectedCountry.dialCode,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                color: AppTheme.textSecondary,
                              ),
                            ],
                          ),
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
