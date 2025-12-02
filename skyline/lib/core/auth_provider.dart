import 'dart:io';
import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  Map<String, dynamic>? _user;
  List<dynamic> _rideHistory = [];
  DateTime? _lastRideHistoryFetch;

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;
  List<dynamic> get rideHistory => _rideHistory;

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
      if (e.toString().contains("User not found") || e.toString().contains("Unauthorized")) {
        await logout();
      }
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
      if (e.toString().contains("User not found") || e.toString().contains("Driver not found") || e.toString().contains("Unauthorized")) {
        await logout();
      }
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

  Future<bool> deleteVehicleImage(String publicId) async {
    try {
      final response = await _apiService.deleteVehicleImage(publicId);
      if (response['success'] == true) {
         // Update local user data
         if (_user != null && _user!['vehicleImages'] != null) {
            final updatedUser = Map<String, dynamic>.from(_user!);
            final List<dynamic> images = List.from(updatedUser['vehicleImages']);
            final List<dynamic> publicIds = List.from(updatedUser['vehicleImagePublicIds'] ?? []);
            
            // Find index of publicId to remove corresponding image URL
            final index = publicIds.indexOf(publicId);
            if (index != -1) {
              if (index < images.length) {
                images.removeAt(index);
              }
              publicIds.removeAt(index);
              
              updatedUser['vehicleImages'] = images;
              updatedUser['vehicleImagePublicIds'] = publicIds;
              _user = updatedUser;
              notifyListeners();
            }
         }
         return true;
      }
    } catch (e) {
      print('Error deleting vehicle image: $e');
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

  Future<bool> updateDriverProfile(Map<String, dynamic> data) async {
    try {
      final response = await _apiService.updateDriverProfile(data);
      if (response['success'] == true && response['data'] != null) {
         // Update local user data
         _user = response['data'];
         notifyListeners();
         return true;
      }
    } catch (e) {
      print('Error updating driver profile: $e');
    }
    return false;
  }

  Future<void> fetchRideHistory({bool forceRefresh = false}) async {
    // Smart Caching: Return cached data if less than 5 minutes old and not forced
    if (!forceRefresh && 
        _rideHistory.isNotEmpty && 
        _lastRideHistoryFetch != null && 
        DateTime.now().difference(_lastRideHistoryFetch!) < const Duration(minutes: 5)) {
      debugPrint('📦 [AuthProvider] Returning cached ride history');
      return;
    }

    try {
      final response = await _apiService.getRideHistory();
      if (response['success'] == true && response['data'] != null) {
        _rideHistory = response['data'];
        _lastRideHistoryFetch = DateTime.now();
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching ride history: $e');
    }
  }

  Future<Map<String, dynamic>?> fetchRideDetails(String rideId) async {
    try {
      final response = await _apiService.getRideDetails(rideId);
      if (response['success'] == true && response['data'] != null) {
        return response['data'];
      }
    } catch (e) {
      print('Error fetching ride details: $e');
    }
    return null;
  }

  Future<void> logout() async {
    _isAuthenticated = false;
    _user = null;
    _rideHistory = [];
    _lastRideHistoryFetch = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    notifyListeners();
  }
}
