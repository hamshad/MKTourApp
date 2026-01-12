import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'api_service.dart';
import 'services/socket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  Map<String, dynamic>? _user;
  List<dynamic> _rideHistory = [];
  DateTime? _lastRideHistoryFetch;
  String? _role;
  Map<String, dynamic>? _driverProfileStatus;

  static const String _prefsAuthTokenKey = 'auth_token';
  static const String _prefsAuthRoleKey = 'auth_role';
  static const String _prefsDriverProfileStatusKey = 'driver_profile_status';

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;
  List<dynamic> get rideHistory => _rideHistory;
  String? get role => _role;
  bool get isDriver => _role == 'driver';
  Map<String, dynamic>? get driverProfileStatus => _driverProfileStatus;

  Future<bool> login(String email, String password) async {
    try {
      final response = await _apiService.login(email, password);
      if (response['success']) {
        _isAuthenticated = true;
        _user = response['user'];
        _role = 'user';
        await SocketService().initSocket();
        notifyListeners();
        return true;
      }
    } catch (e) {
      print(e);
    }
    return false;
  }

  Future<bool> signup(
    String email,
    String password,
    String firstName,
    String lastName,
  ) async {
    try {
      final response = await _apiService.signup(
        email,
        password,
        firstName,
        lastName,
      );
      if (response['success']) {
        _isAuthenticated = true;
        _user = response['user'];
        _role = 'user';
        await SocketService().initSocket();
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
        _role = 'user';
        await SocketService().initSocket();
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      if (e.toString().contains("User not found") ||
          e.toString().contains("Unauthorized")) {
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
        _role = 'driver';
        await SocketService().initSocket();
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching driver profile: $e');
      if (e.toString().contains("User not found") ||
          e.toString().contains("Driver not found") ||
          e.toString().contains("Unauthorized")) {
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
          final List<dynamic> publicIds = List.from(
            updatedUser['vehicleImagePublicIds'] ?? [],
          );

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
      if (!prefs.containsKey(_prefsAuthTokenKey)) {
        return false;
      }

      _role = prefs.getString(_prefsAuthRoleKey) ?? 'user';

      // Load cached driver profileStatus immediately (may be refreshed below).
      if (_role == 'driver') {
        _loadCachedDriverProfileStatus(prefs);
      }

      if (_role == 'driver') {
        await fetchDriverProfile();

        // On app re-open, refresh current driver profile status.
        // If it fails (offline), the cached status remains available.
        try {
          await fetchDriverProfileStatus();
        } catch (_) {}
      } else {
        await fetchUserProfile();
      }
      return _isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  void _loadCachedDriverProfileStatus(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsDriverProfileStatusKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _driverProfileStatus = decoded;
      } else if (decoded is Map) {
        _driverProfileStatus = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Ignore cache decode issues.
    }
  }

  Future<void> fetchDriverProfileStatus() async {
    final response = await _apiService.getDriverProfileStatus();
    if (response['success'] == true && response['data'] != null) {
      final data = response['data'];
      final profileStatus = (data is Map && data['profileStatus'] != null)
          ? data['profileStatus']
          : data;
      if (profileStatus is Map<String, dynamic>) {
        _driverProfileStatus = profileStatus;
      } else if (profileStatus is Map) {
        _driverProfileStatus = Map<String, dynamic>.from(profileStatus);
      }
      notifyListeners();
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

  Future<bool> updateUser({
    required String name,
    required String email,
    File? profilePicture,
  }) async {
    try {
      final response = await _apiService.updateUserProfile(
        name: name,
        email: email,
        profilePicture: profilePicture,
      );

      if (response['success'] == true && response['data'] != null) {
        _user = response['data'];
        notifyListeners();
        return true;
      }
    } catch (e) {
      print('Error updating user profile: $e');
    }
    return false;
  }

  Future<void> fetchRideHistory({bool forceRefresh = false}) async {
    debugPrint(
      '📦 [AuthProvider] fetchRideHistory called (forceRefresh: $forceRefresh)',
    );

    // Smart Caching: Return cached data if less than 5 minutes old and not forced
    if (!forceRefresh &&
        _rideHistory.isNotEmpty &&
        _lastRideHistoryFetch != null &&
        DateTime.now().difference(_lastRideHistoryFetch!) <
            const Duration(minutes: 5)) {
      debugPrint(
        '📦 [AuthProvider] Returning cached ride history (${_rideHistory.length} rides)',
      );
      return;
    }

    try {
      debugPrint('📦 [AuthProvider] Fetching ride history from API...');
      final response = await _apiService.getRideHistory();
      debugPrint(
        '📦 [AuthProvider] API Response: success=${response['success']}, data type=${response['data']?.runtimeType}',
      );

      if (response['success'] == true && response['data'] != null) {
        _rideHistory = List<Map<String, dynamic>>.from(response['data']);
        _lastRideHistoryFetch = DateTime.now();
        debugPrint(
          '📦 [AuthProvider] Ride history updated: ${_rideHistory.length} rides',
        );
        if (_rideHistory.isNotEmpty) {
          debugPrint(
            '📦 [AuthProvider] First ride status: ${_rideHistory.first['status']}',
          );
        }
        notifyListeners();
      } else {
        debugPrint('📦 [AuthProvider] API returned success=false or no data');
      }
    } catch (e) {
      debugPrint('❌ [AuthProvider] Error fetching ride history: $e');
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
    _role = null;
    _driverProfileStatus = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsAuthTokenKey);
    await prefs.remove(_prefsAuthRoleKey);
    await prefs.remove(_prefsDriverProfileStatusKey);
    SocketService().disconnect();
    notifyListeners();
  }
}
