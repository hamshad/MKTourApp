import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';

class EditDriverProfileScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;

  const EditDriverProfileScreen({super.key, required this.driverData});

  @override
  State<EditDriverProfileScreen> createState() => _EditDriverProfileScreenState();
}

class _EditDriverProfileScreenState extends State<EditDriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _vehicleModelController;
  late TextEditingController _vehicleNumberController;
  late TextEditingController _vehicleColorController;
  bool _isLoading = false;
  
  String? _selectedVehicleType;
  final List<String> _vehicleTypes = ['sedan', 'suv', 'hatchback', 'van'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.driverData['name']);
    _emailController = TextEditingController(text: widget.driverData['email']);
    
    final vehicle = widget.driverData['vehicle'] ?? {};
    _selectedVehicleType = vehicle['type'];
    if (_selectedVehicleType != null && !_vehicleTypes.contains(_selectedVehicleType)) {
      _selectedVehicleType = null; // Handle case where existing type is not in list
    }
    
    _vehicleModelController = TextEditingController(text: vehicle['model']);
    _vehicleNumberController = TextEditingController(text: vehicle['number']);
    _vehicleColorController = TextEditingController(text: vehicle['color']);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();

    _vehicleModelController.dispose();
    _vehicleNumberController.dispose();
    _vehicleColorController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final updatedData = {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'vehicle': {
        'type': _selectedVehicleType,
        'model': _vehicleModelController.text.trim(),
        'number': _vehicleNumberController.text.trim(),
        'color': _vehicleColorController.text.trim(),
      }
    };

    final success = await Provider.of<AuthProvider>(context, listen: false)
        .updateDriverProfile(updatedData);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile'), backgroundColor: Colors.red),
        );
      }
    }
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
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Personal Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildTextField('Full Name', _nameController, Icons.person),
              const SizedBox(height: 16),
              _buildTextField('Email', _emailController, Icons.email, keyboardType: TextInputType.emailAddress),
              
              const SizedBox(height: 32),
              
              const Text('Vehicle Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              // Vehicle Type Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                  color: AppTheme.surfaceColor,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedVehicleType,
                    isExpanded: true,
                    hint: Row(
                      children: [
                        const Icon(Icons.directions_car, color: AppTheme.textSecondary),
                        const SizedBox(width: 12),
                        const Text(
                          'Select Vehicle Type',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                        ),
                      ],
                    ),
                    items: _vehicleTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car, color: AppTheme.textPrimary),
                            const SizedBox(width: 12),
                            Text(
                              type[0].toUpperCase() + type.substring(1),
                              style: const TextStyle(color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedVehicleType = value),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              _buildTextField('Vehicle Model (e.g., Toyota Camry)', _vehicleModelController, Icons.local_taxi),
              const SizedBox(height: 16),
              _buildTextField('Vehicle Number', _vehicleNumberController, Icons.confirmation_number),
              const SizedBox(height: 16),
              _buildTextField('Vehicle Color', _vehicleColorController, Icons.color_lens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, {TextInputType? keyboardType}) {
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
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        filled: true,
        fillColor: AppTheme.surfaceColor,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        return null;
      },
    );
  }
}
