# Skyline Project Documentation

## Overview
Skyline is a ride-hailing application built with Flutter. It features separate flows for Passengers and Drivers, a comprehensive authentication system, and a modern, premium UI design.

## Core Architecture
The project follows a feature-based directory structure located in `lib/features`.
- **Core**: Contains shared utilities, theme, and services (`lib/core`).
- **Features**: Contains feature-specific screens and logic (`lib/features`).

### Key Core Files
- **Theme**: `lib/core/theme.dart` - Defines the application's color palette (Orange accent), typography (Google Fonts Outfit), and component styles.
- **API Service**: `lib/core/api_service.dart` - Handles all HTTP requests to the backend (Auth, OTP, etc.).
- **Auth Provider**: `lib/core/auth_provider.dart` - Manages authentication state using Provider.
- **Widgets**: `lib/core/widgets/custom_snackbar.dart` - A standardized custom snackbar for in-app notifications.

---

## 1. Authentication Flow
The authentication system supports both Passengers and Drivers, using phone number verification and OTP.

### Flow Steps:
1.  **Splash Screen**: `lib/features/auth/splash_screen.dart` - Initial loading screen.
2.  **Intro/Onboarding**: `lib/features/onboarding/intro_screen.dart` - Introduces the app features.
3.  **Login/Signup Entry**: `lib/features/auth/login_screen.dart` - Main entry point.
    - *Action*: User clicks "Sign in" or "Sign up".
4.  **Role Selection**: `lib/features/auth/role_selection_screen.dart` - User chooses to continue as "Passenger" or "Driver".
5.  **Phone Login**: `lib/features/auth/phone_login_screen.dart` - User enters phone number.
    - *Logic*: Checks if user exists.
    - *If New User*: Navigates to `NameInputScreen`.
    - *If Existing User*: Sends OTP and navigates to Registration/OTP screen.
6.  **Name Input (New Users)**: `lib/features/auth/name_input_screen.dart` - Collects name for new registrations.
7.  **OTP Verification**:
    - **Passenger**: `lib/features/auth/user_registration_screen.dart` - Verifies OTP for passengers.
    - **Driver**: `lib/features/auth/driver_registration_screen.dart` - Verifies OTP and collects vehicle details for drivers.

---

## 2. Passenger Flow
The main flow for users booking rides.

### Screens & Files:
- **Home**: `lib/features/home/home_screen.dart`
    - Displays map, current location, and nearby cars.
    - Bottom Navigation: Home, Activity (`lib/features/home/activity_screen.dart`), Account (`lib/features/home/account_screen.dart`).
- **Booking**:
    1.  **Destination Search**: `lib/features/booking/destination_search_screen.dart` - User searches for a drop-off location.
    2.  **Vehicle Selection**: `lib/features/booking/vehicle_selection_panel.dart` - User selects car type (Standard, Premium, etc.) and views fare estimates.
    3.  **Confirm Booking**: `lib/features/booking/confirm_booking_screen.dart` - Final confirmation before requesting a ride.
- **Ride Progress**:
    - **Ride Assigned**: `lib/features/ride/ride_assigned_screen.dart` - Shows driver details when a driver accepts.
    - **Ride In Progress**: `lib/features/ride/ride_progress_screen.dart` - Tracks the ride in real-time.
    - **Ride Complete**: `lib/features/ride/ride_complete_screen.dart` - Summary and rating after the ride ends.

---

## 3. Driver Flow
The flow for drivers to accept rides and manage their earnings.

### Screens & Files:
- **Registration**: `lib/features/auth/driver_registration_screen.dart` - Collects vehicle info (Model, Plate, Color) during signup.
- **Home**: `lib/features/driver/driver_home_screen.dart` - Main dashboard for drivers to go online/offline and accept ride requests.
- **Ride Management**:
    - **Driver Assigned**: `lib/features/ride/driver_assigned_screen.dart` - View for driver when assigned to a passenger.
    - **Ride Detail**: `lib/features/driver/driver_ride_detail_screen.dart` - Detailed view of a specific ride.
- **Profile & Earnings**:
    - **Profile**: `lib/features/driver/driver_profile_screen.dart` - Driver settings and info.
    - **Earnings**: `lib/features/driver/driver_earnings_screen.dart` - Dashboard for daily/weekly earnings.
    - **Activity**: `lib/features/driver/driver_activity_screen.dart` - History of completed rides.

---

## 4. Onboarding Extras
Additional screens for setting up the user profile.
- **Marketing Consent**: `lib/features/onboarding/marketing_consent_screen.dart`
- **Payment Method**: `lib/features/onboarding/payment_method_screen.dart`

## Navigation
Navigation is managed via named routes defined in `lib/main.dart`.
- **Key Routes**: `/login`, `/home`, `/driver-home`, `/role-selection`, `/ride-progress`.

## Recent Refactors
- **Theme**: Unified Orange (`#FFFF6B35`) accent color across the app.
- **UI Polish**: `LoginScreen`, `PhoneLoginScreen`, `RoleSelectionScreen`, `UserRegistrationScreen`, and `DriverRegistrationScreen` have been refactored to use `GoogleFonts.outfit` and a cleaner, premium design.
