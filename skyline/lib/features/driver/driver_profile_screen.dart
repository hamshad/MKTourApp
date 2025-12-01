import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../auth/phone_login_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    await Provider.of<AuthProvider>(context, listen: false).fetchDriverProfile();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadVehicleImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      
      if (images.isEmpty) return;

      if (!mounted) return;

      if (images.length > 5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only upload a maximum of 5 images'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _isLoading = true);
      final files = images.map((xFile) => File(xFile.path)).toList();
      
      if (!mounted) return;
      final success = await Provider.of<AuthProvider>(context, listen: false)
          .uploadVehicleImages(files);
      
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Vehicle images uploaded successfully' : 'Failed to upload images'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking images: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadLicense() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        if (!mounted) return;
        setState(() => _isLoading = true);
        final file = File(image.path);
        
        final success = await Provider.of<AuthProvider>(context, listen: false)
            .uploadDriverLicense(file);
        
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? 'License uploaded successfully' : 'Failed to upload license'),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking license: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Library'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickProfileImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickProfileImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        if (!mounted) return;
        setState(() => _isLoading = true);
        final file = File(image.path);
        
        final success = await Provider.of<AuthProvider>(context, listen: false)
            .updateProfilePicture(file);
        
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? 'Profile picture updated successfully' : 'Failed to update profile picture'),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open document')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProfile,
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final driver = authProvider.user;
          debugPrint('🔵 [DriverProfileScreen] Driver Data: $driver');
          
          if (driver == null) {
            return const Center(child: Text('Failed to load profile'));
          }

          final vehicle = driver['vehicle'] ?? {};
          debugPrint('🔵 [DriverProfileScreen] Vehicle Data: $vehicle');
          
          final rawVehicleImages = driver['vehicleImages'];
          debugPrint('🔵 [DriverProfileScreen] Raw Vehicle Images: $rawVehicleImages (${rawVehicleImages.runtimeType})');
          
          final List<String> vehicleImages = (rawVehicleImages is List) 
              ? rawVehicleImages.map((e) => e.toString()).toList() 
              : [];
              
          final licenseDoc = driver['licenseDocument'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Profile Header
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: AppTheme.surfaceColor,
                            backgroundImage: driver['profilePicture'] != null
                                ? NetworkImage(driver['profilePicture'])
                                : null,
                            child: driver['profilePicture'] == null
                                ? const Icon(Icons.person, size: 60, color: AppTheme.textSecondary)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _showImageSourceActionSheet,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        driver['name'] ?? 'Driver Name',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Active since ${driver['createdAt'] != null ? DateTime.parse(driver['createdAt']).year : 'N/A'}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 16, color: AppTheme.accentColor),
                            const SizedBox(width: 4),
                            Text(
                              '${driver['rating'] ?? 0} Rating',
                              style: const TextStyle(
                                color: AppTheme.accentColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Stats Grid
                Row(
                  children: [
                    _buildStatCard('Total Rides', '${driver['totalRides'] ?? 0}', Icons.directions_car),
                    const SizedBox(width: 16),
                    _buildStatCard('Acceptance', '98%', Icons.check_circle), // Mock data for now
                    const SizedBox(width: 16),
                    _buildStatCard('Cancel Rate', '1%', Icons.cancel), // Mock data for now
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Vehicle Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Vehicle Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.upload_file, color: AppTheme.primaryColor),
                      onPressed: _uploadVehicleImages,
                      tooltip: 'Upload Vehicle Images',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: vehicleImages.isNotEmpty 
                                ? () => _launchURL(vehicleImages.first)
                                : null,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor,
                                borderRadius: BorderRadius.circular(12),
                                image: vehicleImages.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(vehicleImages.first),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: vehicleImages.isEmpty
                                  ? const Icon(Icons.local_taxi, size: 32, color: AppTheme.textSecondary)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicle['model'] ?? 'No Vehicle',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${vehicle['color'] ?? ''} • ${vehicle['type'] ?? ''}',
                                  style: const TextStyle(color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              vehicle['number'] ?? 'N/A',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (vehicleImages.length > 1) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 60,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: vehicleImages.length - 1,
                            itemBuilder: (context, index) {
                              return GestureDetector(
                                onTap: () => _launchURL(vehicleImages[index + 1]),
                                child: Container(
                                  width: 60,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image: DecorationImage(
                                      image: NetworkImage(vehicleImages[index + 1]),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Documents
                _buildMenuItem(
                  Icons.description, 
                  'Documents', 
                  licenseDoc != null ? 'License Uploaded' : 'Upload License',
                  onTap: _uploadLicense,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (licenseDoc != null)
                        IconButton(
                          icon: const Icon(Icons.visibility, color: AppTheme.primaryColor),
                          onPressed: () => _launchURL(licenseDoc),
                          tooltip: 'View License',
                        ),
                      Icon(
                        licenseDoc != null ? Icons.check_circle : Icons.upload, 
                        color: licenseDoc != null ? Colors.green : AppTheme.primaryColor
                      ),
                    ],
                  ),
                ),
                _buildMenuItem(Icons.payment, 'Payout Settings', 'Bank Account'),
                _buildMenuItem(Icons.settings, 'App Settings', 'Navigation, Sound'),
                _buildMenuItem(
                  Icons.logout, 
                  'Log Out', 
                  '', 
                  isDestructive: true,
                  onTap: () async {
                    // Use AuthProvider to logout
                    await Provider.of<AuthProvider>(context, listen: false).logout();
                    
                    // Navigate to login screen
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PhoneLoginScreen(role: 'driver'),
                      ),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: AppTheme.primaryColor),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    IconData icon, 
    String title, 
    String subtitle, {
    bool isDestructive = false,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDestructive ? Colors.red.withValues(alpha: 0.1) : AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isDestructive ? Colors.red : AppTheme.textPrimary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDestructive ? Colors.red : AppTheme.textPrimary,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      onTap: onTap ?? () {},
    );
  }
}
