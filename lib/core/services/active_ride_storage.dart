import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the in-progress ride id + role so the app can restore the correct
/// status screen after a full app restart (kill + reopen). Without this, both the
/// driver and passenger lose their active-ride state on restart.
///
/// Also persists the trip-state blob for the new ride flow — stops[],
/// wait totals, adjusted fare, payment state, and current stop index — so a
/// restart mid-trip restores stops, wait fees, and payment state, including
/// the `at_stop` pause (via `currentStopIndex` + `stops[]`).
///
/// Migration-tolerant: every getter falls back to a default when its key is
/// missing (older installs), and JSON decoding never throws.
///
/// NOTE: ride verification code is intentionally NOT persisted here. The new
/// backend flow starts rides without code verification, so no ride code is
/// stored on device.
/// (Auth/login OTP uses the API send/verify endpoints and is untouched.)
class ActiveRideStorage {
  static const String _idKey = 'active_ride_id';
  static const String _roleKey = 'active_ride_role';
  static const String _statusKey = 'active_ride_status';
  static const String _stopsKey = 'active_ride_stops';
  static const String _waitMinutesKey = 'active_ride_wait_minutes';
  static const String _waitFeeKey = 'active_ride_wait_fee';
  static const String _actualFareKey = 'active_ride_actual_fare';
  static const String _paymentMethodKey = 'active_ride_payment_method';
  static const String _paymentStatusKey = 'active_ride_payment_status';
  static const String _stopIndexKey = 'active_ride_stop_index';
  static const String _savedAtKey = 'active_ride_saved_at';

  // Scheduled-ride metadata — persisted so a cold-start restores the
  // scheduled-ride UI without re-fetching.
  static const String _scheduledPickupTimeKey = 'active_ride_scheduled_pickup_time';
  static const String _scheduledStatusKey = 'active_ride_scheduled_status';
  static const String _scheduledPaymentMethodKey = 'active_ride_scheduled_payment_method';

  /// Rides older than this are treated as stale on cold start and cleared.
  static const Duration staleAfter = Duration(hours: 24);

  /// Final statuses that must never restore — always clear + home.
  static const Set<String> finalStatuses = {
    'completed',
    'early_completed',
    'cancelled',
    'cancelled_by_user',
    'cancelled_by_driver',
    'expired',
  };

  /// Legacy ride-code key — no longer written. Removed on [clear] so stale
  /// values from older installs don't linger.
  static const String _legacyOtpKey = 'active_ride_otp';

  /// Save (or update) the active ride. [role] is 'driver' or 'passenger'.
  static Future<void> save({
    required String rideId,
    required String role,
    String? status,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_idKey, rideId);
    await prefs.setString(_roleKey, role);
    await prefs.setString(_savedAtKey, DateTime.now().toIso8601String());
    if (status != null) await prefs.setString(_statusKey, status);
  }

  static Future<void> updateStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statusKey, status);
  }

  /// Persist the mid-trip state blob (stops, wait totals, fare, payment).
  ///
  /// [stops] is the raw stops list from the backend (JSON-encodable maps).
  /// Any argument left null keeps its previously stored value.
  static Future<void> saveTripState({
    List<dynamic>? stops,
    int? totalWaitMinutes,
    double? totalWaitFee,
    double? actualFare,
    String? paymentMethod,
    String? paymentStatus,
    int? currentStopIndex,
    String? scheduledPickupTime,
    String? scheduledStatus,
    String? scheduledPaymentMethod,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (stops != null) {
      await prefs.setString(_stopsKey, jsonEncode(stops));
    }
    if (totalWaitMinutes != null) {
      await prefs.setInt(_waitMinutesKey, totalWaitMinutes);
    }
    if (totalWaitFee != null) await prefs.setDouble(_waitFeeKey, totalWaitFee);
    if (actualFare != null) await prefs.setDouble(_actualFareKey, actualFare);
    if (paymentMethod != null) {
      await prefs.setString(_paymentMethodKey, paymentMethod);
    }
    if (paymentStatus != null) {
      await prefs.setString(_paymentStatusKey, paymentStatus);
    }
    if (currentStopIndex != null) {
      await prefs.setInt(_stopIndexKey, currentStopIndex);
    }
    if (scheduledPickupTime != null) {
      await prefs.setString(_scheduledPickupTimeKey, scheduledPickupTime);
    }
    if (scheduledStatus != null) {
      await prefs.setString(_scheduledStatusKey, scheduledStatus);
    }
    if (scheduledPaymentMethod != null) {
      await prefs.setString(_scheduledPaymentMethodKey, scheduledPaymentMethod);
    }
  }

  /// Read the persisted trip-state blob. Missing keys → defaults, never throws.
  static Future<Map<String, dynamic>> getTripState() async {
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> stops = [];
    final rawStops = prefs.getString(_stopsKey);
    if (rawStops != null && rawStops.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawStops);
        if (decoded is List) stops = decoded;
      } catch (_) {
        stops = [];
      }
    }
    return {
      'stops': stops,
      'totalWaitMinutes': prefs.getInt(_waitMinutesKey) ?? 0,
      'totalWaitFee': prefs.getDouble(_waitFeeKey) ?? 0.0,
      'actualFare': prefs.getDouble(_actualFareKey) ?? 0.0,
      'paymentMethod': prefs.getString(_paymentMethodKey),
      'paymentStatus': prefs.getString(_paymentStatusKey),
      'currentStopIndex': prefs.getInt(_stopIndexKey) ?? 0,
      'scheduledPickupTime': prefs.getString(_scheduledPickupTimeKey),
      'scheduledStatus': prefs.getString(_scheduledStatusKey),
      'scheduledPaymentMethod': prefs.getString(_scheduledPaymentMethodKey),
    };
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

  /// True when the stored ride is older than [staleAfter] or missing a
  /// timestamp (pre-timestamp installs) — caller should [clear] + home.
  static Future<bool> isStale() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedAtKey);
    if (raw == null || raw.isEmpty) return true;
    try {
      final savedAt = DateTime.parse(raw);
      return DateTime.now().difference(savedAt) > staleAfter;
    } catch (_) {
      return true;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_idKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_statusKey);
    await prefs.remove(_stopsKey);
    await prefs.remove(_waitMinutesKey);
    await prefs.remove(_waitFeeKey);
    await prefs.remove(_actualFareKey);
    await prefs.remove(_paymentMethodKey);
    await prefs.remove(_paymentStatusKey);
    await prefs.remove(_stopIndexKey);
    await prefs.remove(_savedAtKey);
    await prefs.remove(_legacyOtpKey);
    await prefs.remove(_scheduledPickupTimeKey);
    await prefs.remove(_scheduledStatusKey);
    await prefs.remove(_scheduledPaymentMethodKey);
  }
}
