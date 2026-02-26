import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/auth_provider.dart';
import '../../core/constants/privacy_policy.dart';
import '../auth/role_selection_screen.dart';
import 'pdf_viewer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  void _showPrivacyPolicy() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Privacy Policy',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  Text(privacyPolicy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount() {
    final rootContext = context;
    showDialog(
      context: rootContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action is irreversible and you will lose all your data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final authProvider = Provider.of<AuthProvider>(rootContext, listen: false);
              
              showDialog(
                context: rootContext,
                barrierDismissible: false,
                builder: (progressContext) => const Center(child: CircularProgressIndicator()),
              );

              final success = await authProvider.deleteAccount();

              if (!mounted) return;
              Navigator.pop(rootContext); // Close progress dialog

              if (success) {
                final message = authProvider.lastDeleteMessage ?? 'Account deleted successfully.';
                showDialog(
                  context: rootContext,
                  barrierDismissible: false,
                  builder: (resultContext) => AlertDialog(
                    title: const Text('Account Deleted'),
                    content: Text(message),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(resultContext).pop();
                          Navigator.of(rootContext).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const RoleSelectionScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              } else {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(content: Text('Failed to delete account. Please try again.')),
                );
              }
            
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('Privacy \u0026 Security'),
          _buildLinkItem('Privacy Policy', onTap: _showPrivacyPolicy),
          _buildLinkItem(
            'Customer Complaint Policy',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PdfViewerScreen(
                  title: 'Customer Complaint Policy',
                  assetPath: 'assets/customer_complaint_policy.pdf',
                ),
              ),
            ),
          ),
          _buildLinkItem(
            'Data Protection Policy',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PdfViewerScreen(
                  title: 'Data Protection Policy',
                  assetPath: 'assets/data_protection_complaint_policy.pdf',
                ),
              ),
            ),
          ),
          _buildLinkItem(
            'Payment Security & PCI Compliance',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PdfViewerScreen(
                  title: 'Payment Security & PCI Compliance',
                  assetPath: 'assets/payment_security_pci_compliance.pdf',
                ),
              ),
            ),
          ),
          _buildLinkItem(
            'Terms & Conditions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PdfViewerScreen(
                  title: 'Terms & Conditions',
                  assetPath: 'assets/terms_and_conditions.pdf',
                ),
              ),
            ),
          ),
          _buildLinkItem(
            'Delete Account',
            isDestructive: true,
            onTap: _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildLinkItem(String title, {bool isDestructive = false, VoidCallback? onTap}) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: isDestructive ? Colors.red : AppTheme.textPrimary,
          fontWeight: isDestructive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      onTap: onTap,
    );
  }
}
