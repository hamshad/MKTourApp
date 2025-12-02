import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../auth/phone_login_screen.dart';
import 'edit_driver_profile_screen.dart';
import '../../core/widgets/pdf_viewer_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool _isLoading = false;
  bool _isVehicleUploading = false;
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;

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

      // Check size limit (3MB per image)
      for (var image in images) {
        final file = File(image.path);
        final sizeInBytes = await file.length();
        if (sizeInBytes > 3 * 1024 * 1024) { // 3MB
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Each image must be less than 3MB'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      setState(() => _isVehicleUploading = true);
      final files = images.map((xFile) => File(xFile.path)).toList();
      
      if (!mounted) return;
      final success = await Provider.of<AuthProvider>(context, listen: false)
          .uploadVehicleImages(files);
      
      if (mounted) {
        setState(() => _isVehicleUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Vehicle images uploaded successfully' : 'Failed to upload images'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isVehicleUploading = false);
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
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);
        
        // Check size limit (5MB)
        final sizeInBytes = await file.length();
        if (sizeInBytes > 5 * 1024 * 1024) { // 5MB
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Document must be less than 5MB'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (!mounted) return;
        setState(() => _isLoading = true);
        
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
        final file = File(image.path);

        // Check size limit (5MB)
        final sizeInBytes = await file.length();
        if (sizeInBytes > 5 * 1024 * 1024) { // 5MB
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture must be less than 5MB'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (!mounted) return;
        setState(() => _isLoading = true);
        
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

  void _showFullScreenImage(List<String> images, int initialIndex, {List<String>? publicIds}) {
    PageController pageController = PageController(initialPage: initialIndex);
    int currentIndex = initialIndex;
    bool isDeleting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PageView.builder(
                  controller: pageController,
                  itemCount: images.length,
                  onPageChanged: (index) {
                    setState(() => currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: images[index],
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (publicIds != null && publicIds.length > currentIndex && !isDeleting)
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
                          ),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Image'),
                                content: const Text('Are you sure you want to delete this image?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              setState(() => isDeleting = true);
                              if (!mounted) return;
                              
                              final success = await Provider.of<AuthProvider>(context, listen: false)
                                  .deleteVehicleImage(publicIds[currentIndex]);
                              
                              if (mounted) {
                                setState(() => isDeleting = false);
                                if (success) {
                                  Navigator.pop(context); // Close fullscreen to refresh
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Image deleted successfully'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to delete image'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                if (isDeleting)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                if (images.length > 1 && !isDeleting) ...[
                  if (currentIndex > 0)
                    Positioned(
                      left: 10,
                      child: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_left, color: Colors.white, size: 30),
                        ),
                        onPressed: () {
                          pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                  if (currentIndex < images.length - 1)
                    Positioned(
                      right: 10,
                      child: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_right, color: Colors.white, size: 30),
                        ),
                        onPressed: () {
                          pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          );
        }
      ),
    );
  }

  Future<void> _launchURL(String urlString, {String title = 'Document'}) async {
    debugPrint('🔵 [_launchURL] Attempting to launch: $urlString');
    try {
      final Uri uri = Uri.parse(urlString);
      bool isPdf = uri.path.toLowerCase().endsWith('.pdf');
      debugPrint('🔵 [_launchURL] Initial extension check: isPdf=$isPdf');

      if (!isPdf) {
        // Check for PDF signature (magic bytes) and Content-Type
        try {
          debugPrint('🔵 [_launchURL] Checking file signature/headers...');
          final response = await http.get(
            uri, 
            headers: {'Range': 'bytes=0-9'} // Fetch first 10 bytes
          );
          
          debugPrint('🔵 [_launchURL] Head/Range response status: ${response.statusCode}');
          debugPrint('🔵 [_launchURL] Content-Type: ${response.headers['content-type']}');

          if (response.statusCode == 200 || response.statusCode == 206) {
            // Check magic bytes for PDF: %PDF-
            // We use bodyBytes to check the raw bytes
            final bytes = response.bodyBytes;
            debugPrint('🔵 [_launchURL] First ${bytes.length} bytes: $bytes');
            
            if (bytes.length >= 4 && 
                bytes[0] == 0x25 && // %
                bytes[1] == 0x50 && // P
                bytes[2] == 0x44 && // D
                bytes[3] == 0x46) { // F
              isPdf = true;
              debugPrint('🟢 [_launchURL] PDF magic bytes detected!');
            }
            
            // Also check Content-Type header as backup
            if (!isPdf && response.headers['content-type']?.toLowerCase().contains('application/pdf') == true) {
              isPdf = true;
              debugPrint('🟢 [_launchURL] PDF Content-Type detected!');
            }
          }
        } catch (e) {
          debugPrint('🔴 [_launchURL] Error checking file type: $e');
        }
      }

      if (isPdf) {
        debugPrint('🟢 [_launchURL] Opening as PDF in internal viewer');
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(url: urlString, title: title),
            ),
          );
        }
      } else {
        debugPrint('🟡 [_launchURL] Not a PDF, launching externally');
        // For non-PDF documents (doc, docx), launch externally
        // inAppBrowserView often fails for direct file downloads/viewing
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          debugPrint('🔴 [_launchURL] Failed to launch external URL');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open document')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('🔴 [_launchURL] Critical error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid URL')),
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
            icon: const Icon(Icons.edit),
            onPressed: () {
              final driver = Provider.of<AuthProvider>(context, listen: false).user;
              if (driver != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EditDriverProfileScreen(driverData: driver),
                  ),
                ).then((_) => _fetchProfile());
              }
            },
          ),
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
          
          if (driver == null) {
            return const Center(child: Text('Failed to load profile'));
          }

          final vehicle = driver['vehicle'] ?? {};
          final rawVehicleImages = driver['vehicleImages'];
          final List<String> vehicleImages = (rawVehicleImages is List) 
              ? rawVehicleImages.map((e) => e.toString()).toList() 
              : [];
          final rawPublicIds = driver['vehicleImagePublicIds'];
          final List<String> vehicleImagePublicIds = (rawPublicIds is List)
              ? rawPublicIds.map((e) => e.toString()).toList()
              : [];
          final licenseDoc = driver['licenseDocument'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              children: [
                // Profile Header
                Column(
                  children: [
                    Stack(
                      children: [
                        GestureDetector(
                          onTap: driver['profilePicture'] != null 
                              ? () => _showFullScreenImage([driver['profilePicture']], 0) 
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.primaryColor, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: AppTheme.surfaceColor,
                              backgroundImage: driver['profilePicture'] != null
                                  ? CachedNetworkImageProvider(driver['profilePicture'])
                                  : null,
                              child: driver['profilePicture'] == null
                                  ? const Icon(Icons.person, size: 60, color: AppTheme.textSecondary)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _showImageSourceActionSheet,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      driver['name'] ?? 'Driver Name',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 20, color: Colors.amber),
                          const SizedBox(width: 6),
                          Text(
                            '${driver['rating'] ?? 5.0} Rating',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Stats Grid
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('${driver['totalRides'] ?? 0}', 'Rides', Icons.local_taxi),
                      Container(width: 1, height: 40, color: AppTheme.borderColor),
                      _buildStatItem('98%', 'Acceptance', Icons.check_circle_outline),
                      Container(width: 1, height: 40, color: AppTheme.borderColor),
                      _buildStatItem('4.9', 'Rating', Icons.thumb_up_outlined),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Vehicle Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Vehicle Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _uploadVehicleImages,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                      label: const Text('Add Photos'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.directions_car_filled, color: AppTheme.primaryColor, size: 32),
                                ),
                                const SizedBox(width: 20),
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
                                      const SizedBox(height: 4),
                                      Text(
                                        '${vehicle['color'] ?? ''} ${vehicle['type'] ?? ''}'.trim(),
                                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.borderColor),
                                  ),
                                  child: Text(
                                    vehicle['number'] ?? 'N/A',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (vehicleImages.isNotEmpty) ...[
                            const Divider(height: 1),
                            const SizedBox(height: 16),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1,
                              ),
                              itemCount: vehicleImages.length,
                              itemBuilder: (context, index) {
                                return GestureDetector(
                                  onTap: () => _showFullScreenImage(vehicleImages, index, publicIds: vehicleImagePublicIds),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image: CachedNetworkImageProvider(vehicleImages[index]),
                                        fit: BoxFit.cover,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                      if (_isVehicleUploading)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Documents & Settings
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Documents & Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      _buildMenuItem(
                        Icons.description_outlined, 
                        'Driver License', 
                        licenseDoc != null ? 'Verified' : 'Action Required',
                        onTap: () {
                          if (licenseDoc != null) {
                            _launchURL(licenseDoc, title: 'Driver License');
                          } else {
                            _uploadLicense();
                          }
                        },
                        trailing: licenseDoc != null 
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('View', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              )
                            : const Icon(Icons.upload_file, color: AppTheme.primaryColor),
                        showDivider: true,
                      ),
                      _buildMenuItem(Icons.account_balance_wallet_outlined, 'Payout Settings', 'Bank Account', showDivider: true),
                      _buildMenuItem(Icons.settings_outlined, 'App Settings', 'Navigation, Sound', showDivider: true),
                      _buildMenuItem(
                        Icons.logout_rounded, 
                        'Log Out', 
                        '', 
                        isDestructive: true,
                        onTap: () async {
                          await Provider.of<AuthProvider>(context, listen: false).logout();
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PhoneLoginScreen(role: 'driver'),
                            ),
                            (route) => false,
                          );
                        },
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: AppTheme.primaryColor),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
    IconData icon, 
    String title, 
    String subtitle, {
    bool isDestructive = false,
    VoidCallback? onTap,
    Widget? trailing,
    bool showDivider = false,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDestructive ? Colors.red.withValues(alpha: 0.1) : AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: isDestructive ? Colors.red : AppTheme.textPrimary,
              size: 22,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: isDestructive ? Colors.red : AppTheme.textPrimary,
            ),
          ),
          subtitle: subtitle.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                )
              : null,
          trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 20),
          onTap: onTap ?? () {},
        ),
        if (showDivider)
          const Divider(height: 1, indent: 70, endIndent: 20),
      ],
    );
  }
}
