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
import 'features/ride/ride_assigned_screen.dart';

void main() {
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
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/onboarding': (context) => const IntroScreen(),
        '/marketing-consent': (context) => const MarketingConsentScreen(),
        '/payment-method': (context) => const PaymentMethodScreen(),
        '/home': (context) => const HomeScreen(),
        '/destination-search': (context) => const DestinationSearchScreen(),
        '/vehicle-selection': (context) => const VehicleSelectionScreen(),
        '/confirm-booking': (context) => const ConfirmBookingScreen(),
        '/ride-assigned': (context) => const RideAssignedScreen(),
      },
    );
  }
}
