import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_service.dart';

/// Background message handler - must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized
  await Firebase.initializeApp();
  debugPrint('🔔 [FCM] Background message received: ${message.messageId}');
  debugPrint('🔔 [FCM] Data: ${message.data}');

  // Handle background notification
  await FcmService.instance.handleBackgroundMessage(message);
}

/// Notification types from backend
class NotificationType {
  // User App Notifications
  static const String rideAccepted = 'ride_accepted';
  static const String driverArrived = 'driver_arrived';
  static const String rideStarted = 'ride_started';
  static const String otpExpired = 'otp_expired';
  static const String rideCompleted = 'ride_completed';
  static const String rideEarlyCompleted = 'ride_early_completed';
  static const String rideCancelledByDriver = 'ride_cancelled_by_driver';
  static const String rideCancelledTimeout = 'ride_cancelled_timeout';
  static const String cashCollected = 'cash_collected';
  static const String rideExpired = 'ride_expired';
  static const String rideLongRunning = 'ride_long_running';

  // Driver App Notifications
  static const String rideRequest = 'ride_request';
  static const String rideCancelled = 'ride_cancelled';
  static const String rideCancelledByUser = 'ride_cancelled_by_user';
  static const String paymentSelected = 'payment_selected';
  static const String rideReminder = 'ride_reminder';

  // Promo Notifications (User)
  static const String promoUnlocked = 'promo_unlocked';
  static const String promoApplied = 'promo_applied';
  static const String promoClaimed = 'promo_claimed';
}

/// FCM Notification payload data
class FcmNotificationData {
  final String type;
  final String? rideId;
  final String? otp;
  final String? newOTP;
  final double? fare;
  final double? amount;
  final double? originalFare;
  final String? promoStatus;
  final String? reason;
  final String? paymentMethod;
  final String? driverName;
  final String? pickupAddress;
  final Map<String, dynamic> rawData;

  FcmNotificationData({
    required this.type,
    this.rideId,
    this.otp,
    this.newOTP,
    this.fare,
    this.amount,
    this.originalFare,
    this.promoStatus,
    this.reason,
    this.paymentMethod,
    this.driverName,
    this.pickupAddress,
    required this.rawData,
  });

  factory FcmNotificationData.fromMap(Map<String, dynamic> data) {
    return FcmNotificationData(
      type: data['type'] ?? '',
      rideId: data['rideId'],
      otp: data['otp'],
      newOTP: data['newOTP'] ?? data['newOtp'],
      fare: _parseDouble(data['fare']),
      amount: _parseDouble(data['amount']),
      originalFare: _parseDouble(data['originalFare']),
      promoStatus: data['promoStatus'],
      reason: data['reason'],
      paymentMethod: data['paymentMethod'],
      driverName: data['driverName'] ?? data['name'],
      pickupAddress: data['pickupAddress'] ?? data['pickup'],
      rawData: data,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// FCM Service for handling Firebase Cloud Messaging
class FcmService {
  static final FcmService _instance = FcmService._internal();
  static FcmService get instance => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _fcmToken;

  // Stream controllers for notification events
  final StreamController<FcmNotificationData>
  _foregroundNotificationController =
      StreamController<FcmNotificationData>.broadcast();
  final StreamController<FcmNotificationData> _notificationTapController =
      StreamController<FcmNotificationData>.broadcast();

  /// Stream of foreground notifications
  Stream<FcmNotificationData> get onForegroundNotification =>
      _foregroundNotificationController.stream;

  /// Stream of notification taps (when user taps on notification)
  Stream<FcmNotificationData> get onNotificationTap =>
      _notificationTapController.stream;

  /// Current FCM token
  String? get fcmToken => _fcmToken;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize FCM Service
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('🔔 [FCM] Already initialized');
      return;
    }

    try {
      debugPrint('🔔 [FCM] Initializing FCM Service...');

      // Request permission
      await _requestPermission();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Get FCM token
      await _getFcmToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_onTokenRefresh);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check for initial notification (app opened from terminated state)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '🔔 [FCM] App opened from terminated state with notification',
        );
        _handleNotificationTap(initialMessage);
      }

      _isInitialized = true;
      debugPrint('🔔 [FCM] FCM Service initialized successfully');
      debugPrint('🔔 [FCM] Token: $_fcmToken');
    } catch (e) {
      debugPrint('🔴 [FCM] Error initializing FCM Service: $e');
    }
  }

  /// Request notification permission
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('🔔 [FCM] Permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('🔔 [FCM] User granted permission');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      debugPrint('🔔 [FCM] User granted provisional permission');
    } else {
      debugPrint('🔴 [FCM] User declined or has not accepted permission');
    }
  }

  /// Initialize local notifications for foreground display
  Future<void> _initializeLocalNotifications() async {
    // Android settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );

    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create Android notification channel
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'mktours_rides',
        'MK Tours Rides',
        description: 'Notifications for ride updates',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      debugPrint('🔔 [FCM] Android notification channel created');
    }
  }

  /// Get FCM token
  Future<String?> _getFcmToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      debugPrint('🔔 [FCM] Token retrieved: $_fcmToken');

      // Store token locally
      if (_fcmToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _fcmToken!);
      }

      return _fcmToken;
    } catch (e) {
      debugPrint('🔴 [FCM] Error getting token: $e');
      return null;
    }
  }

  /// Handle token refresh
  void _onTokenRefresh(String newToken) async {
    debugPrint('🔔 [FCM] Token refreshed: $newToken');
    _fcmToken = newToken;

    // Store new token locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', newToken);

    // TODO: Send new token to backend
    // This will be handled by auth_provider when it detects token change
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 [FCM] Foreground message received');
    debugPrint('🔔 [FCM] Title: ${message.notification?.title}');
    debugPrint('🔔 [FCM] Body: ${message.notification?.body}');
    debugPrint('🔔 [FCM] Data: ${message.data}');

    final data = FcmNotificationData.fromMap(message.data);

    // Play notification sound for important notifications
    _playNotificationSound(data.type);

    // Show local notification
    _showLocalNotification(message);

    // Emit to stream for in-app handling
    _foregroundNotificationController.add(data);
  }

  /// Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('🔔 [FCM] Notification tapped');
    debugPrint('🔔 [FCM] Data: ${message.data}');

    final data = FcmNotificationData.fromMap(message.data);
    _notificationTapController.add(data);
  }

  /// Handle background message (static method for background handler)
  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('🔔 [FCM] Processing background message: ${message.data}');
    // Background messages are handled by the system notification tray
    // The app will handle navigation when user taps the notification
  }

  /// Local notification tap handler
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 [FCM] Local notification tapped');
    debugPrint('🔔 [FCM] Payload: ${response.payload}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        final notificationData = FcmNotificationData.fromMap(data);
        _notificationTapController.add(notificationData);
      } catch (e) {
        debugPrint('🔴 [FCM] Error parsing notification payload: $e');
      }
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'mktours_rides',
      'MK Tours Rides',
      channelDescription: 'Notifications for ride updates',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  /// Play notification sound based on notification type
  void _playNotificationSound(String type) {
    // Play sound for important notifications
    switch (type) {
      case NotificationType.rideRequest:
      case NotificationType.rideAccepted:
      case NotificationType.driverArrived:
      case NotificationType.rideStarted:
      case NotificationType.rideCompleted:
      case NotificationType.promoUnlocked:
      case NotificationType.promoApplied:
      case NotificationType.promoClaimed:
        AudioService.instance.playNotification();
        break;
      default:
        // No sound for other notification types
        break;
    }
  }

  /// Get stored FCM token from SharedPreferences
  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fcm_token');
  }

  /// Force token refresh
  Future<String?> refreshToken() async {
    try {
      await _messaging.deleteToken();
      return await _getFcmToken();
    } catch (e) {
      debugPrint('🔴 [FCM] Error refreshing token: $e');
      return null;
    }
  }

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('🔔 [FCM] Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('🔴 [FCM] Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('🔔 [FCM] Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('🔴 [FCM] Error unsubscribing from topic: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _foregroundNotificationController.close();
    _notificationTapController.close();
  }
}

/// Mixin for handling FCM notifications in screens/widgets
mixin FcmNotificationHandler<T extends StatefulWidget> on State<T> {
  StreamSubscription<FcmNotificationData>? _foregroundSubscription;
  StreamSubscription<FcmNotificationData>? _tapSubscription;

  @override
  void initState() {
    super.initState();
    _setupFcmListeners();
  }

  @override
  void dispose() {
    _foregroundSubscription?.cancel();
    _tapSubscription?.cancel();
    super.dispose();
  }

  void _setupFcmListeners() {
    _foregroundSubscription = FcmService.instance.onForegroundNotification
        .listen(onFcmNotification);
    _tapSubscription = FcmService.instance.onNotificationTap.listen(
      onFcmNotificationTap,
    );
  }

  /// Override this to handle foreground notifications
  void onFcmNotification(FcmNotificationData data) {
    debugPrint('🔔 [FCM Handler] Received notification: ${data.type}');

    switch (data.type) {
      case NotificationType.rideRequest:
        onRideRequest(data);
        break;
      case NotificationType.rideAccepted:
        onRideAccepted(data);
        break;
      case NotificationType.driverArrived:
        onDriverArrived(data);
        break;
      case NotificationType.rideStarted:
        onRideStarted(data);
        break;
      case NotificationType.otpExpired:
        onOtpExpired(data);
        break;
      case NotificationType.rideCompleted:
        onRideCompleted(data);
        break;
      case NotificationType.rideEarlyCompleted:
        onRideEarlyCompleted(data);
        break;
      case NotificationType.rideCancelledByDriver:
        onRideCancelledByDriver(data);
        break;
      case NotificationType.rideCancelledByUser:
        onRideCancelledByUser(data);
        break;
      case NotificationType.rideCancelledTimeout:
        onRideCancelledTimeout(data);
        break;
      case NotificationType.rideCancelled:
        onRideCancelled(data);
        break;
      case NotificationType.paymentSelected:
        onPaymentSelected(data);
        break;
      case NotificationType.cashCollected:
        onCashCollected(data);
        break;
      case NotificationType.rideExpired:
        onRideExpired(data);
        break;
      case NotificationType.rideReminder:
        onRideReminder(data);
        break;
      case NotificationType.rideLongRunning:
        onRideLongRunning(data);
        break;
      case NotificationType.promoUnlocked:
        onPromoUnlocked(data);
        break;
      case NotificationType.promoApplied:
        onPromoApplied(data);
        break;
      case NotificationType.promoClaimed:
        onPromoClaimed(data);
        break;
      default:
        debugPrint('🔔 [FCM Handler] Unknown notification type: ${data.type}');
    }
  }

  /// Override this to handle notification taps
  void onFcmNotificationTap(FcmNotificationData data) {
    debugPrint('🔔 [FCM Handler] Notification tapped: ${data.type}');
    // Default: navigate based on notification type
    // Override in subclass for specific navigation
  }

  // User App notification handlers
  void onRideAccepted(FcmNotificationData data) {}
  void onDriverArrived(FcmNotificationData data) {}
  void onRideStarted(FcmNotificationData data) {}
  void onOtpExpired(FcmNotificationData data) {}
  void onRideCompleted(FcmNotificationData data) {}
  void onRideEarlyCompleted(FcmNotificationData data) {}
  void onRideCancelledByDriver(FcmNotificationData data) {}
  void onRideCancelledTimeout(FcmNotificationData data) {}
  void onCashCollected(FcmNotificationData data) {}

  // Driver App notification handlers
  void onRideRequest(FcmNotificationData data) {}
  void onRideCancelled(FcmNotificationData data) {}
  void onRideCancelledByUser(FcmNotificationData data) {}
  void onPaymentSelected(FcmNotificationData data) {}
  void onRideReminder(FcmNotificationData data) {}

  // Common notification handlers
  void onRideExpired(FcmNotificationData data) {}
  void onRideLongRunning(FcmNotificationData data) {}

  // Promo notification handlers
  void onPromoUnlocked(FcmNotificationData data) {}
  void onPromoApplied(FcmNotificationData data) {}
  void onPromoClaimed(FcmNotificationData data) {}
}
