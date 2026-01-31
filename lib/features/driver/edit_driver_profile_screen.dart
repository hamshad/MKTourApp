import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/vehicle_service.dart';

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
  
  String? _selectedCategorySlug;
  List<VehicleCategory> _categories = [];
  bool _isLoadingCategories = true;
  final VehicleService _vehicleService = VehicleService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.driverData['name']);
    _emailController = TextEditingController(text: widget.driverData['email']);
    
    final vehicle = widget.driverData['vehicle'] ?? {};
    _selectedCategorySlug = vehicle['categorySlug'];
    
    _vehicleModelController = TextEditingController(text: vehicle['model']);
    _vehicleNumberController = TextEditingController(text: vehicle['number']);
    _vehicleColorController = TextEditingController(text: vehicle['color']);

    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _vehicleService.getVehicleCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoadingCategories = false;
          // Ensure selected category is still valid
          if (_selectedCategorySlug != null && 
              !categories.any((c) => c.slug == _selectedCategorySlug)) {
             // If not found in dynamic list, keep it but it might need re-selection
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
      if (mounted) {
        setState(() {
          _categories = _vehicleService.defaultCategories;
          _isLoadingCategories = false;
        });
      }
    }
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
    if (!_formKey.currentState!.validate() || _selectedCategorySlug == null) {
      if (_selectedCategorySlug == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a vehicle category'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    final updatedData = {
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'vehicle': {
        'categorySlug': _selectedCategorySlug,
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
      body: _isLoadingCategories 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
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
              
              // Vehicle Category Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor),
                  color: AppTheme.surfaceColor,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategorySlug,
                    isExpanded: true,
                    hint: const Row(
                      children: [
                        Icon(Icons.directions_car, color: AppTheme.textSecondary),
                        SizedBox(width: 12),
                        Text(
                          'Select Vehicle Category',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                        ),
                      ],
                    ),
                    items: _categories.map((category) {
                      return DropdownMenuItem(
                        value: category.slug,
                        child: Row(
                          children: [
                            const Icon(Icons.directions_car, color: AppTheme.textPrimary),
                            const SizedBox(width: 12),
                            Text(
                              category.name == category.slug || category.name == 'Unknown'
                                ? VehicleCategory.formatSlug(category.slug)
                                : category.name,
                              style: const TextStyle(color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedCategorySlug = value),
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
