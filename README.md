# Skyline (RideEase)

Skyline is a comprehensive ride-sharing application mockup built with **Flutter** for the frontend and **Node.js** for the backend. It demonstrates a complete user journey for both **Passengers** and **Drivers**, featuring a modern UI/UX inspired by leading ride-hailing apps.

## 🚀 Features

### 👤 Passenger Experience
- **Authentication**: Seamless Login and Signup flows.
- **Onboarding**: Interactive intro, marketing consent, and payment method setup.
- **Home & Map**: Real-time map view with simulated nearby vehicles.
- **Booking Flow**:
    - Destination search with suggestions.
    - Vehicle selection (Economy, Premium, etc.) with fare estimates.
    - Booking confirmation and driver assignment.
- **Ride Experience**:
    - Live ride progress tracking (simulated).
    - Driver details and vehicle information.
    - Ride completion and rating.

### 🚗 Driver Experience
- **Driver Dashboard**: Toggle online/offline status.
- **Ride Requests**: Receive and accept/reject ride requests.
- **Navigation**: Turn-by-turn navigation simulation to pickup and drop-off locations.
- **Earnings & Activity**:
    - Track daily and weekly earnings.
    - View detailed ride history and activity logs.
- **Profile**: Manage driver profile and settings.

## 🛠️ Tech Stack

- **Frontend**: Flutter (Dart)
    - `provider` for state management.
    - `flutter_map` & `latlong2` for mapping.
    - `sliding_up_panel` for bottom sheets.
    - `lottie` for animations.
- **Backend**: Node.js (Express)
    - Mock API endpoints for auth, booking, and ride status.

## 📋 Prerequisites

- **Flutter**: 3.9.2 or higher ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Node.js**: 16.x or higher ([Install Node.js](https://nodejs.org/))

## ⚙️ Setup Instructions

### 1. Backend Setup
The backend simulates the server-side logic and must be running for the app to function correctly.

```bash
cd backend
npm install
node server.js
```
*Server runs on `http://localhost:3000`*

### 2. Frontend Setup
Run the Flutter application on your preferred device or emulator.

```bash
cd skyline
flutter pub get
```

**Run on iOS Simulator:**
```bash
flutter run -d ios
```

**Run on Android Emulator:**
```bash
flutter run -d android
```

## 🎯 Usage Guide

1.  **Start the Backend**: Ensure `node server.js` is running.
2.  **Launch the App**: Open the app on a simulator/emulator.
3.  **Login/Signup**: Use any credentials to log in (mock auth).
4.  **Choose Mode**:
    *   **Passenger**: Search for a destination, book a ride, and watch the simulated driver arrive.
    *   **Driver**: Go to the Driver Home (via simulated role switch or direct navigation if implemented), go online, and accept incoming ride requests.

## 📁 Project Structure

```
Skyline/
├── backend/                # Node.js Express Server
│   ├── server.js           # API Endpoints
│   └── package.json
└── skyline/                # Flutter Application
    ├── lib/
    │   ├── core/           # Constants, Theme, Auth Provider
    │   ├── features/
    │   │   ├── auth/       # Login, Signup, Splash
    │   │   ├── booking/    # Destination Search, Vehicle Selection
    │   │   ├── driver/     # Driver Home, Earnings, Profile
    │   │   ├── home/       # Main Map Screen
    │   │   ├── onboarding/ # Intro, Consent, Payment
    │   │   └── ride/       # Ride Progress, Completion
    │   └── main.dart       # App Entry Point
    └── pubspec.yaml
```

## 📝 Notes

- **Mock Data**: This is a demonstration prototype. Payments, driver matching, and location tracking are simulated.
- **Backend Dependency**: The app relies on the local Node.js server for API calls. Ensure it's running on the same network/machine accessible to the emulator (localhost often requires special handling on Android, e.g., `10.0.2.2`).

## 📄 License

This project is for educational and demonstration purposes.
