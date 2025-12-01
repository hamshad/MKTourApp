import 'dart:io';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  Map<String, dynamic>? _user;

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;

  Future<bool> login(String email, String password) async {
    try {
      final response = await _apiService.login(email, password);
      if (response['success']) {
        _isAuthenticated = true;
        _user = response['user'];
        notifyListeners();
        return true;
      }
    } catch (e) {
      print(e);
    }
    return false;
  }

  Future<bool> signup(String email, String password, String firstName, String lastName) async {
    try {
      final response = await _apiService.signup(email, password, firstName, lastName);
      if (response['success']) {
        _isAuthenticated = true;
        _user = response['user'];
        notifyListeners();
        return true;
      }
    } catch (e) {
      print(e);
    }
    return false;
  }

  Future<void> fetchUserProfile() async {
    try {
      final response = await _apiService.getUserProfile();
      if (response['success'] == true && response['data'] != null) {
        _user = response['data'];
        _isAuthenticated = true;
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching user profile: $e');
    }
  }

  Future<void> fetchDriverProfile() async {
    try {
      final response = await _apiService.getDriverProfile();
      if (response['success'] == true && response['data'] != null) {
        _user = response['data']; // Reusing _user for driver data as well
        _isAuthenticated = true;
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching driver profile: $e');
    }
  }

  Future<bool> uploadVehicleImages(List<File> images) async {
    try {
      final response = await _apiService.uploadVehicleImages(images);
      if (response['success'] == true && response['data'] != null) {
         // Update local user data with new images if needed
         if (response['data']['driver'] != null) {
            _user = response['data']['driver'];
            notifyListeners();
         }
         return true;
      }
    } catch (e) {
      print('Error uploading vehicle images: $e');
    }
    return false;
  }

  Future<bool> uploadDriverLicense(File license) async {
    try {
      final response = await _apiService.uploadDriverLicense(license);
      if (response['success'] == true && response['data'] != null) {
         // Update local user data with new license if needed
         if (response['data']['driver'] != null) {
            _user = response['data']['driver'];
            notifyListeners();
         }
         return true;
      }
    } catch (e) {
      print('Error uploading driver license: $e');
    }
    return false;
  }

  Future<bool> checkAuth() async {
    try {
      await fetchUserProfile();
      return _isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  Future<bool> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('auth_token')) {
        return false;
      }
      
      await fetchUserProfile();
      return _isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateProfilePicture(File image) async {
    try {
      final response = await _apiService.updateDriverProfilePicture(image);
      if (response['success'] == true && response['data'] != null) {
         // Update local user data with new profile picture
         if (response['data']['profilePicture'] != null) {
            // Create a new map to ensure immutability isn't an issue if _user was const
            final updatedUser = Map<String, dynamic>.from(_user ?? {});
            updatedUser['profilePicture'] = response['data']['profilePicture'];
            _user = updatedUser;
            notifyListeners();
         }
         return true;
      }
    } catch (e) {
      print('Error updating profile picture: $e');
    }
    return false;
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }
}
