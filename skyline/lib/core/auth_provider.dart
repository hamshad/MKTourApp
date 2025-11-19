import 'package:flutter/material.dart';
import 'api_service.dart';

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

  void logout() {
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }
}
