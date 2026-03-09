import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme.dart';
import 'core/auth_provider.dart';
import 'core/api_service.dart';
import 'core/config/api_config.dart';
import 'core/services/stripe_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/places_service.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/onboarding/intro_screen.dart';
import 'features/onboarding/marketing_consent_screen.dart';
import 'features/onboarding/payment_method_screen.dart';
import 'features/home/home_screen.dart';
import 'features/booking/destination_search_screen.dart';
import 'features/booking/confirm_booking_screen.dart';
import 'features/booking/ride_confirmation_screen.dart';
import 'features/booking/scheduled_rides_screen.dart';
import 'features/ride/driver_assigned_screen.dart';
import 'features/ride/ride_complete_screen.dart';
import 'features/driver/driver_home_screen.dart';
import 'features/ride/ride_progress_screen.dart';
import 'features/driver/driver_profile_screen.dart';
import 'features/driver/driver_earnings_screen.dart';
import 'features/driver/driver_activity_screen.dart';
import 'features/driver/driver_ride_detail_screen.dart';
import 'features/driver/driver_ride_history_screen.dart';
import 'features/driver/document_checklist_screen.dart';
import 'features/driver/vehicle_information_screen.dart';
import 'features/driver/bank_details_screen.dart';
import 'features/auth/role_selection_screen.dart';

import 'core/services/socket_service.dart';
import 'core/services/location_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();
  debugPrint('🔥 Firebase initialized');

  // Initialize environment variables
  await ApiConfig.initialize();

  // Initialize Stripe
  await StripeService.init();

  // Initialize FCM Service for push notifications
  await FcmService.instance.initialize();
  debugPrint('🔔 FCM Service initialized');

  // Initialize Socket Service
  final socketService = SocketService();
  await socketService.initSocket();

  // Preload location in background (non-blocking)
  LocationCacheService().preloadLocation().catchError((e) {
    debugPrint('📍 Failed to preload location: $e');
  });

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthProvider())],
      child: const RideEaseApp(),
    ),
  );
}

class RideEaseApp extends StatelessWidget {
  const RideEaseApp({super.key});

  // Global navigator key for navigation from anywhere
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool get _isMobileStorePlatform {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Widget build(BuildContext context) {
    // Set up 401 unauthorized handler to trigger logout
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    ApiService.onUnauthorized = () async {
      debugPrint('🔴 [RideEaseApp] 401 Unauthorized - Triggering logout');
      await authProvider.logout();
      
      // Navigate to role selection screen after logout
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
      debugPrint('🔴 [RideEaseApp] Navigated to role selection after 401');
    };
    PlacesService.onUnauthorized = () async {
      debugPrint('🔴 [RideEaseApp] 401 Unauthorized from PlacesService - Triggering logout');
      await authProvider.logout();
      
      // Navigate to role selection screen after logout
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
      debugPrint('🔴 [RideEaseApp] Navigated to role selection after 401');
    };
    
    final app = MaterialApp(
      navigatorKey: navigatorKey,
      title: 'RideEase',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
      routes: {
        '/role-selection': (context) => const RoleSelectionScreen(),
        '/signup': (context) => const SignupScreen(),
        '/onboarding': (context) => const IntroScreen(),
        '/marketing-consent': (context) => const MarketingConsentScreen(),
        '/payment-method': (context) => const PaymentMethodScreen(),
        '/home': (context) => const HomeScreen(),
        '/destination-search': (context) => const DestinationSearchScreen(),
        '/confirm-booking': (context) => const ConfirmBookingScreen(),
        '/driver-home': (context) => const DriverHomeScreen(),
        '/ride-progress': (context) => const RideProgressScreen(),
        '/driver-profile': (context) => const DriverProfileScreen(),
        '/driver-earnings': (context) => const DriverEarningsScreen(),
        '/driver-activity': (context) => const DriverActivityScreen(),
        '/driver-ride-history': (context) => const DriverRideHistoryScreen(),
        '/driver/vehicle-info': (context) => const VehicleInformationScreen(),
        '/driver/documents': (context) => const DocumentChecklistScreen(),
        '/driver/bank-details': (context) => const BankDetailsScreen(),
        '/scheduled-rides': (context) => const ScheduledRidesScreen(),
      },
      onGenerateRoute: (settings) {
        // Handle routes with arguments dynamically
        if (settings.name == '/ride-assigned') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => DriverAssignedScreen(bookingData: args ?? {}),
          );
        }
        if (settings.name == '/ride-complete') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => RideCompleteScreen(rideData: args ?? {}),
          );
        }
        if (settings.name == '/driver-ride-detail') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => DriverRideDetailScreen(rideData: args ?? {}),
          );
        }
        if (settings.name == '/ride-confirmation') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => RideConfirmationScreen(
              pickupLocation: args?['pickupLocation'] ?? {},
              dropoffLocation: args?['dropoffLocation'] ?? {},
              categorySlug: args?['categorySlug'] ?? '',
              categoryName: args?['categoryName'] ?? '',
              fareData: args?['fareData'] ?? {},
              polyline: args?['polyline'],
            ),
          );
        }
        return null;
      },
    );

    if (!_isMobileStorePlatform) {
      return app;
    }

    // Skipping the UpgradeAlert wrapper to avoid a missing dependency
    // during CI/builds. Re-enable by adding `upgrader` to pubspec.yaml
    // and restoring the UpgradeAlert wrapper if desired.
    return app;
  }
}
