import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/constants/countries.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';

class EditDriverProfileScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;

  const EditDriverProfileScreen({super.key, required this.driverData});

  @override
  State<EditDriverProfileScreen> createState() =>
      _EditDriverProfileScreenState();
}

class _EditDriverProfileScreenState extends State<EditDriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _otpController;
  bool _isLoading = false;

  Country _selectedCountry = countries.firstWhere((c) => c.dialCode == '+44');
  String? _originalPhone;
  bool _otpSent = false;
  String? _pendingPhone;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.driverData['name'] ?? '');
    _emailController =
        TextEditingController(text: widget.driverData['email'] ?? '');
    _phoneController = TextEditingController();
    _otpController = TextEditingController();

    final phone = widget.driverData['phone'] ?? '';
    _originalPhone = phone.toString();
    _parsePhone(phone.toString());
  }

  void _parsePhone(String fullPhone) {
    if (fullPhone.isEmpty) return;
    for (final c in countries) {
      if (fullPhone.startsWith(c.dialCode)) {
        _selectedCountry = c;
        _phoneController.text = fullPhone.substring(c.dialCode.length);
        return;
      }
    }
    _phoneController.text = fullPhone;
  }

  String _getFullPhone() =>
      '${_selectedCountry.dialCode}${_phoneController.text.trim()}';

  bool get _phoneChanged => _getFullPhone() != _originalPhone;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
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
                  bottom: MediaQuery.of(context).viewInsets.bottom),
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
                      decoration: InputDecoration(
                        hintText: 'Search country',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        setModalState(() {
                          filtered.value = countries
                              .where((c) =>
                                  c.name
                                      .toLowerCase()
                                      .contains(value.toLowerCase()) ||
                                  c.dialCode.contains(value))
                              .toList();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: ValueListenableBuilder<List<Country>>(
                      valueListenable: filtered,
                      builder: (context, list, _) {
                        return ListView.separated(
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = list[index];
                            return ListTile(
                              leading: Text(c.flag,
                                  style: const TextStyle(fontSize: 24)),
                              title: Text(c.name),
                              trailing: Text(
                                c.dialCode,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500,
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
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _validatePhone(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    return digitsOnly.length >= 7;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final newPhone = _getFullPhone();

    if (_phoneChanged && !_validatePhone(newPhone)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid phone number'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_phoneChanged && !_otpSent) {
      setState(() => _isLoading = true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await authProvider.requestPhoneUpdateOtp(newPhone);

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (response['success'] == true) {
        setState(() {
          _otpSent = true;
          _pendingPhone = newPhone;
          _otpController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification code sent to $newPhone'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to send code'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final otp = _otpController.text.trim();
    if (_phoneChanged && _otpSent && otp.length != 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the 6-digit verification code'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    final updatedData = <String, dynamic>{};
    if (_nameController.text.trim().isNotEmpty) {
      updatedData['name'] = _nameController.text.trim();
    }
    if (_emailController.text.trim().isNotEmpty) {
      updatedData['email'] = _emailController.text.trim();
    }
    if (_phoneChanged) {
      updatedData['phone'] = newPhone;
    }
    if (_phoneChanged && _otpSent) {
      updatedData['otp'] = otp;
    }

    final success = await Provider.of<AuthProvider>(context, listen: false)
        .updateDriverProfile(updatedData);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update profile'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _cancelPhoneChange() {
    setState(() {
      _otpSent = false;
      _pendingPhone = null;
      _otpController.clear();
      _phoneController.text = _originalPhone != null
          ? _originalPhone!.replaceFirst(_selectedCountry.dialCode, '')
          : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.save, color: AppTheme.primaryColor),
                  tooltip: 'Save',
                ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Personal Information',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 16),
              _buildTextField('Full Name', _nameController, Icons.person),
              const SizedBox(height: 16),
              _buildTextField('Email', _emailController, Icons.email,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 28),
              _buildPhoneSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      IconData icon, {
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
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
          borderSide:
              const BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        filled: true,
        fillColor: AppTheme.surfaceColor,
      ),
      validator: (value) {
        if (label == 'Email') return null;
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        return null;
      },
    );
  }

  Widget _buildPhoneSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.phone_android,
                size: 18, color: _otpSent ? Colors.green : AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text('Phone Number',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color:
                        _otpSent ? Colors.green.shade700 : AppTheme.textPrimary)),
            if (_otpSent) ...[
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, size: 14, color: Colors.green),
                    SizedBox(width: 4),
                    Text('Code Sent',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Changing your phone number requires verification. '
          'A 6-digit code will be sent to your new number.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            GestureDetector(
              onTap: _otpSent ? null : _showCountryPicker,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                decoration: BoxDecoration(
                  color:
                      _otpSent ? Colors.grey.shade100 : AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.borderColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedCountry.flag,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text(_selectedCountry.dialCode,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    if (!_otpSent)
                      const Icon(Icons.arrow_drop_down,
                          color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _phoneController,
                readOnly: _otpSent,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Phone number',
                  filled: true,
                  fillColor: _otpSent
                      ? Colors.grey.shade100
                      : AppTheme.surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 15),
                ),
              ),
            ),
          ],
        ),
        if (_phoneChanged && !_otpSent) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveProfile,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, size: 18),
              label: Text(_isLoading ? 'Sending...' : 'Send Verification Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
        if (_otpSent && _pendingPhone != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: Colors.blue.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Code sent to $_pendingPhone',
                      style: TextStyle(
                          fontSize: 13, color: Colors.blue.shade800)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (value) {
                    setState(() {});
                    if (value.length == 6) {
                      _saveProfile();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Enter 6-digit code',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppTheme.textSecondary, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppTheme.borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppTheme.borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: AppTheme.primaryColor, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: const Text('Verify',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _cancelPhoneChange,
              child: Text('Cancel',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ),
          ),
        ],
      ],
    );
  }
}
