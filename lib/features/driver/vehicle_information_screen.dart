import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../../core/models/vehicle.dart';
import '../../core/services/vehicle_service.dart';

/// Vehicle Information Update Screen
/// Allows drivers to update vehicle details required before going online
class VehicleInformationScreen extends StatefulWidget {
  const VehicleInformationScreen({super.key});

  @override
  State<VehicleInformationScreen> createState() => _VehicleInformationScreenState();
}

class _VehicleInformationScreenState extends State<VehicleInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _modelController = TextEditingController();
  final _numberController = TextEditingController();
  final _colorController = TextEditingController();
  
  String? _selectedCategorySlug;
  bool _isLoading = false;
  List<VehicleCategory> _categories = [];
  bool _isLoadingCategories = true;
  final VehicleService _vehicleService = VehicleService();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _vehicleService.getVehicleCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
          _isLoadingCategories = false;
        });
        _loadExistingData();
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
      if (mounted) {
        setState(() {
          _categories = _vehicleService.defaultCategories;
          _isLoadingCategories = false;
        });
        _loadExistingData();
      }
    }
  }

  void _loadExistingData() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final vehicle = auth.user?['vehicle'] as Map<String, dynamic>?;
    
    if (vehicle != null) {
      final loadedSlug = vehicle['categorySlug']?.toString();
      // Only set the value if it exists in the available categories list
      if (loadedSlug != null && _categories.any((cat) => cat.slug == loadedSlug)) {
        _selectedCategorySlug = loadedSlug;
      }
      _modelController.text = vehicle['model']?.toString() ?? '';
      _numberController.text = vehicle['number']?.toString() ?? '';
      _colorController.text = vehicle['color']?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _modelController.dispose();
    _numberController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _saveVehicleInfo() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategorySlug == null) {
      CustomSnackbar.show(
        context,
        message: 'Please select a vehicle category',
        type: SnackbarType.error,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      
      final response = await auth.updateVehicleInformation(
        categorySlug: _selectedCategorySlug!,
        model: _modelController.text.trim(),
        number: _numberController.text.trim().toUpperCase(),
        color: _colorController.text.trim(),
      );

      if (mounted) {
        setState(() => _isLoading = false);
        
        if (response['success'] == true) {
          CustomSnackbar.show(
            context,
            message: 'Vehicle information updated successfully',
            type: SnackbarType.success,
          );
          Navigator.pop(context, true);
        } else {
          CustomSnackbar.show(
            context,
            message: response['message'] ?? 'Failed to update vehicle information',
            type: SnackbarType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        CustomSnackbar.show(
          context,
          message: 'Error: $e',
          type: SnackbarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Information'),
      ),
      body: _isLoadingCategories
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Card
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Complete vehicle information is required before you can go online',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Vehicle Category Dropdown
              const Text(
                'Vehicle Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedCategorySlug,
                decoration: InputDecoration(
                  hintText: 'Select category',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.category),
                ),
                items: _categories.map((category) {
                  return DropdownMenuItem(
                    value: category.slug,
                    child: Text(
                      category.name == category.slug || category.name == 'Unknown'
                          ? VehicleCategory.formatSlug(category.slug)
                          : category.name,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedCategorySlug = value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a category';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Vehicle Model
              const Text(
                'Vehicle Model',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _modelController,
                decoration: InputDecoration(
                  hintText: 'e.g., Toyota Prius 2022',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.directions_car),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter vehicle model';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Vehicle Number (Registration)
              const Text(
                'Vehicle Number',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _numberController,
                decoration: InputDecoration(
                  hintText: 'e.g., AB12 CDE',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.confirmation_number),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter vehicle number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Vehicle Color
              const Text(
                'Vehicle Color',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _colorController,
                decoration: InputDecoration(
                  hintText: 'e.g., Black',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.palette),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter vehicle color';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // Save Button
              ElevatedButton(
                onPressed: _isLoading ? null : _saveVehicleInfo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Vehicle Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
