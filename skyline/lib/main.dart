import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/auth_provider.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/onboarding/intro_screen.dart';
import 'features/onboarding/marketing_consent_screen.dart';
import 'features/onboarding/payment_method_screen.dart';
import 'features/home/home_screen.dart';
import 'features/booking/destination_search_screen.dart';
import 'features/booking/vehicle_selection_panel.dart';
import 'features/booking/confirm_booking_screen.dart';
import 'features/ride/driver_assigned_screen.dart';
import 'features/ride/ride_complete_screen.dart';
import 'features/driver/driver_home_screen.dart';
import 'features/ride/ride_progress_screen.dart';
import 'features/driver/driver_profile_screen.dart';
import 'features/driver/driver_earnings_screen.dart';
import 'features/driver/driver_activity_screen.dart';
import 'features/driver/driver_ride_detail_screen.dart';
import 'features/auth/role_selection_screen.dart';

import 'core/services/socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Socket Service
  final socketService = SocketService();
  await socketService.initSocket();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const RideEaseApp(),
    ),
  );
}

class RideEaseApp extends StatelessWidget {
  const RideEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideEase',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
      routes: {
        '/role-selection': (context) => const RoleSelectionScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/onboarding': (context) => const IntroScreen(),
        '/marketing-consent': (context) => const MarketingConsentScreen(),
        '/payment-method': (context) => const PaymentMethodScreen(),
        '/home': (context) => const HomeScreen(),
        '/destination-search': (context) => const DestinationSearchScreen(),
        '/vehicle-selection': (context) => const VehicleSelectionScreen(),
        '/confirm-booking': (context) => const ConfirmBookingScreen(),
        '/driver-home': (context) => const DriverHomeScreen(),
        '/ride-progress': (context) => const RideProgressScreen(),
        '/driver-profile': (context) => const DriverProfileScreen(),
        '/driver-earnings': (context) => const DriverEarningsScreen(),
        '/driver-activity': (context) => const DriverActivityScreen(),
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
        return null;
      },
    );
  }
}
