import 'package:shared_preferences/shared_preferences.dart';

/// Persists the in-progress ride id + role so the app can restore the correct
/// status screen after a full app restart (kill + reopen). Without this, both the
/// driver and passenger lose their active-ride state on restart.
class ActiveRideStorage {
  static const String _idKey = 'active_ride_id';
  static const String _roleKey = 'active_ride_role';
  static const String _statusKey = 'active_ride_status';

  /// Save (or update) the active ride. [role] is 'driver' or 'passenger'.
  static Future<void> save({
    required String rideId,
    required String role,
    String? status,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, rideId);
    await prefs.setString(_roleKey, role);
    if (status != null) await prefs.setString(_statusKey, status);
  }

  static Future<void> updateStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusKey, status);
  }

  static Future<String?> getRideId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_idKey);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  static Future<String?> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_statusKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_statusKey);
  }
}
