# RideEase Mockup (Flutter + Node.js)

A UK-based taxi booking application mockup showcasing core user flows and UI/UX. This is a **demonstration prototype** with simulated backend logic.

## 🚀 Features

- **Authentication Flow**: Splash screen, Login, and Signup
- **Onboarding**: Intro animation, Marketing consent, Payment method selection
- **Home & Map**: Interactive map with nearby taxis and destination search
- **Booking Flow**: Destination search, Vehicle selection, Booking confirmation
- **Ride Experience**: Driver assignment, Ride status simulation

## 📋 Prerequisites

- **Flutter**: 3.9.2 or higher ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Node.js**: 16.x or higher ([Install Node.js](https://nodejs.org/))
- **npm**: Comes with Node.js

## 🛠️ Setup Instructions

### Backend Setup (Node.js)

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Start the server:
   ```bash
   node server.js
   ```

   The server will run on `http://localhost:3000`

### Frontend Setup (Flutter)

1. Navigate to the Flutter project directory:
   ```bash
   cd skyline
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app:
   ```bash
   # For iOS Simulator (macOS only)
   flutter run -d ios

   # For Android Emulator
   flutter run -d android

   # For Chrome (web)
   flutter run -d chrome
   ```

## 🎯 Usage Flow

1. **Launch App**: See splash screen with fade-in animation
2. **Login/Signup**: Use any email and password (mock authentication)
3. **Onboarding**: Complete the intro, marketing consent, and payment method selection
4. **Home Screen**: View map with your location and nearby taxis
5. **Book a Ride**:
   - Tap the search bar
   - Select a destination
   - Choose a vehicle type
   - Confirm booking
6. **Ride Experience**: See driver details and simulated ride status updates

## 📁 Project Structure

```
.
├── backend/
│   ├── server.js          # Express server with mock endpoints
│   └── package.json
└── skyline/
    ├── lib/
    │   ├── core/          # Theme, constants, API service
    │   ├── features/      # Feature modules (auth, home, booking, ride)
    │   └── main.dart      # App entry point
    ├── pubspec.yaml       # Flutter dependencies
    └── test/              # Widget tests
```

## 🧪 Testing

Run Flutter tests:
```bash
cd skyline
flutter test
```

## ⚙️ API Endpoints (Backend)

- `POST /api/login` - Mock user login
- `POST /api/signup` - Mock user signup
- `POST /api/book` - Create a booking and assign driver
- `GET /api/ride-status` - Get current ride status
- `POST /api/reset-ride` - Reset ride status (for testing)

## 🎨 Design Philosophy

- **British Minimalism**: Clean, calm colors with gentle spacing
- **Smooth Transitions**: Bottom sheets and animations for better UX
- **Map-Centered UX**: Similar to Uber/Bolt with familiar patterns

## 📝 Notes

- This is a **mockup/demo** - no real payments, driver matching, or live tracking
- Backend uses static/mock data for demonstration purposes
- The app uses fallback mock responses if the backend is unavailable

## 🚧 Known Limitations

- No real-time driver location updates
- No actual payment processing
- No SMS/email notifications
- Destination autocomplete uses static suggestions
- Ride status simulation is time-based, not event-driven

## 📄 License

This is a demonstration project for educational purposes.
