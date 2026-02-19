import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../core/auth_provider.dart';
import '../../core/models/driver_document.dart';
import '../../core/theme.dart';
import '../../core/widgets/custom_snackbar.dart';
import '../../core/widgets/pdf_viewer_screen.dart';
import '../../core/constants/api_constants.dart';

/// Document Checklist Screen for Driver Registration
/// Shows Section 1 (License) and Section 2 (Vehicle Documents)
/// Allows uploading, viewing, and deleting documents
class DocumentChecklistScreen extends StatefulWidget {
  const DocumentChecklistScreen({super.key});

  @override
  State<DocumentChecklistScreen> createState() => _DocumentChecklistScreenState();
}

class _DocumentChecklistScreenState extends State<DocumentChecklistScreen> {
  bool _isLoading = false;
  final Map<String, bool> _uploadingStates = {};
  final ImagePicker _imagePicker = ImagePicker();
  Map<String, dynamic>? _driverProfile;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.fetchDriverProfile();
      await auth.fetchDriverProfileStatus();
      _driverProfile = auth.user;
    } catch (e) {
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Failed to load status: $e',
          type: SnackbarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _getDocumentUrl(DocumentType docType) {
    if (_driverProfile == null) return null;
    
    String? rawUrl;
    // Map document types to their corresponding fields in the driver profile
    // Document URLs are stored at the top level of the driver object
    switch (docType) {
      case DocumentType.licenseFront:
        rawUrl = _driverProfile!['licenseFront'];
        break;
      case DocumentType.licenseBack:
        rawUrl = _driverProfile!['licenseBack'];
        break;
      case DocumentType.dbsCertificate:
        rawUrl = _driverProfile!['dbsCertificate'];
        break;
      case DocumentType.privateHireLicence:
        rawUrl = _driverProfile!['privateHireLicence'];
        break;
      case DocumentType.roadTax:
        rawUrl = _driverProfile!['roadTax'];
        break;
      case DocumentType.mot:
        rawUrl = _driverProfile!['mot'];
        break;
      case DocumentType.insurance:
        rawUrl = _driverProfile!['insurance'];
        break;
    }
    
    if (rawUrl == null) return null;
    
    // Remove "undefined" if it appears at the start
    if (rawUrl.startsWith('undefined')) {
      rawUrl = rawUrl.replaceFirst('undefined', '');
    }
    
    // If URL is relative (starts with / or doesn't contain http/https), prepend the socketUrl
    if (rawUrl.startsWith('/') || (!rawUrl.contains('http://') && !rawUrl.contains('https://'))) {
      return '${ApiConstants.socketUrl}$rawUrl';
    }
    
    return rawUrl;
  }

  Future<void> _pickAndUploadDocument(DocumentType docType) async {
    try {
      // Show picker options
      final source = await _showPickerDialog();
      if (source == null) return;

      File? file;
      
      if (source == 'camera') {
        final XFile? photo = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (photo != null) {
          file = File(photo.path);
        }
      } else if (source == 'gallery') {
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        if (image != null) {
          file = File(image.path);
        }
      } else if (source == 'files') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'heic'],
        );
        if (result != null && result.files.single.path != null) {
          file = File(result.files.single.path!);
        }
      }

      if (file == null) return;

      // Check file size (max 10MB)
      final sizeInBytes = await file.length();
      if (sizeInBytes > 10 * 1024 * 1024) {
        if (!mounted) return;
        CustomSnackbar.show(
          context,
          message: 'File must be less than 10MB',
          type: SnackbarType.error,
        );
        return;
      }

      // Upload
      setState(() => _uploadingStates[docType.apiKey] = true);

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final response = await auth.uploadDocument(docType.apiKey, file);

      if (mounted) {
        setState(() => _uploadingStates[docType.apiKey] = false);
        
        if (response['success'] == true) {
          CustomSnackbar.show(
            context,
            message: '${docType.displayName} uploaded successfully',
            type: SnackbarType.success,
          );
        } else {
          CustomSnackbar.show(
            context,
            message: response['message'] ?? 'Upload failed',
            type: SnackbarType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingStates[docType.apiKey] = false);
        CustomSnackbar.show(
          context,
          message: 'Error uploading document: $e',
          type: SnackbarType.error,
        );
      }
    }
  }

  Future<String?> _showPickerDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Files (PDF, DOC)'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDocument(DocumentType docType) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete ${docType.displayName}?'),
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

    if (confirm != true) return;

    try {
      setState(() => _uploadingStates[docType.apiKey] = true);

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final response = await auth.deleteDocument(docType.apiKey);

      if (mounted) {
        setState(() => _uploadingStates[docType.apiKey] = false);
        
        if (response['success'] == true) {
          CustomSnackbar.show(
            context,
            message: '${docType.displayName} deleted successfully',
            type: SnackbarType.info,
          );
        } else {
          CustomSnackbar.show(
            context,
            message: response['message'] ?? 'Deletion failed',
            type: SnackbarType.error,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingStates[docType.apiKey] = false);
        CustomSnackbar.show(
          context,
          message: 'Error deleting document: $e',
          type: SnackbarType.error,
        );
      }
    }
  }

  Future<void> _viewDocument(DocumentType docType) async {
    final url = _getDocumentUrl(docType);
    if (url == null) {
      CustomSnackbar.show(
        context,
        message: 'Document URL not available',
        type: SnackbarType.error,
      );
      return;
    }
    
    await _launchURL(url, title: docType.displayName);
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
          final response = await http.head(uri);

          debugPrint(
            '🔵 [_launchURL] Head response status: ${response.statusCode}',
          );
          debugPrint(
            '🔵 [_launchURL] Content-Type: ${response.headers['content-type']}',
          );

          if (response.statusCode == 200) {
            // Check Content-Type header
            final contentType = response.headers['content-type']?.toLowerCase() ?? '';
            if (contentType.contains('application/pdf') || contentType.contains('pdf')) {
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
              builder: (context) =>
                  PdfViewerScreen(url: urlString, title: title),
            ),
          );
        }
      } else {
        debugPrint('🟡 [_launchURL] Not a PDF, launching externally');
        // For non-PDF documents (doc, docx, images), launch externally
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          debugPrint('🔴 [_launchURL] Failed to launch external URL');
          if (mounted) {
            CustomSnackbar.show(
              context,
              message: 'Could not open document',
              type: SnackbarType.error,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('🔴 [_launchURL] Critical error launching URL: $e');
      if (mounted) {
        CustomSnackbar.show(
          context,
          message: 'Invalid URL',
          type: SnackbarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Documents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<AuthProvider>(
              builder: (context, auth, _) {
                final statusData = auth.driverProfileStatus;
                
                if (statusData == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('Unable to load document status'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _refreshStatus,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final profileStatus = DriverProfileStatus.fromJson(statusData);

                return RefreshIndicator(
                  onRefresh: _refreshStatus,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Status Card
                      _buildStatusCard(profileStatus),
                      const SizedBox(height: 24),

                      // Section 1: License Documents
                      _buildSectionHeader('Section 1: Driving License'),
                      const SizedBox(height: 12),
                      ...DocumentType.section1.map(
                        (docType) => _buildDocumentTile(docType, profileStatus),
                      ),
                      const SizedBox(height: 24),

                      // Section 2: Vehicle Documents
                      _buildSectionHeader('Section 2: Vehicle Documents'),
                      const SizedBox(height: 12),
                      ...DocumentType.section2.map(
                        (docType) => _buildDocumentTile(docType, profileStatus),
                      ),
                      const SizedBox(height: 24),

                      // Info Card
                      _buildInfoCard(),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusCard(DriverProfileStatus status) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (status.canGoOnline) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'Approved - You can go online!';
    } else if (status.isComplete && status.verificationStatus == 'pending') {
      statusColor = Colors.orange;
      statusIcon = Icons.pending;
      statusText = 'Pending Admin Approval';
    } else if (status.verificationStatus == 'rejected') {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusText = 'Profile Rejected - Please contact support';
    } else {
      statusColor = Colors.blue;
      statusIcon = Icons.upload_file;
      statusText = 'Complete your profile (${status.missingDocumentCount} items remaining)';
    }

    return Card(
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile Status',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildDocumentTile(DocumentType docType, DriverProfileStatus status) {
    final isMissing = status.isDocumentMissing(docType);
    final isUploading = _uploadingStates[docType.apiKey] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isMissing ? Colors.red.shade100 : Colors.green.shade100,
          child: Icon(
            isMissing ? Icons.error_outline : Icons.check_circle,
            color: isMissing ? Colors.red : Colors.green,
          ),
        ),
        title: Text(
          docType.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isMissing ? 'Not uploaded' : 'Uploaded',
          style: TextStyle(
            color: isMissing ? Colors.red : Colors.green,
            fontSize: 12,
          ),
        ),
        trailing: isUploading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isMissing
                ? IconButton(
                    icon: const Icon(
                      Icons.upload_file,
                      color: AppTheme.primaryColor,
                    ),
                    onPressed: () => _pickAndUploadDocument(docType),
                    tooltip: 'Upload',
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.visibility,
                          color: Colors.blue,
                        ),
                        onPressed: () => _viewDocument(docType),
                        tooltip: 'View',
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          color: AppTheme.primaryColor,
                        ),
                        onPressed: () => _pickAndUploadDocument(docType),
                        tooltip: 'Reupload',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteDocument(docType),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Important Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '• Upload clear, readable copies of all documents\n'
              '• Supported formats: JPG, PNG, PDF, DOC, HEIC\n'
              '• Maximum file size: 10MB per document\n'
              '• All documents must be valid and not expired\n'
              '• Admin will review within 24-48 hours',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
