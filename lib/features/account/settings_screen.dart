import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          _buildSectionHeader('Preferences'),
          _buildSettingItem('Notifications', true),
          _buildSettingItem('Location Access', true),
          _buildSettingItem('Dark Mode', false),
          
          _buildSectionHeader('Privacy & Security'),
          _buildLinkItem('Privacy Policy'),
          _buildLinkItem('Terms of Service'),
          _buildLinkItem('Delete Account', isDestructive: true),
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

  Widget _buildSettingItem(String title, bool value) {
    return SwitchListTile(
      value: value,
      onChanged: (v) {},
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: AppTheme.textPrimary,
        ),
      ),
      activeColor: AppTheme.primaryColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  Widget _buildLinkItem(String title, {bool isDestructive = false}) {
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
      onTap: () {},
    );
  }
}
