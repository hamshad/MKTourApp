class AppConstants {
  // Use 10.0.2.2 for Android Emulator, localhost for iOS Simulator
  // For simplicity in this mockup, we might need to adjust based on platform or just use localhost if running on iOS Sim
  static const String apiBaseUrl = 'http://localhost:3000/api'; 
  
  static const List<Map<String, dynamic>> vehicleTypes = [
    {
      'id': 'standard',
      'name': 'Standard',
      'description': 'Affordable, everyday rides',
      'seats': 4,
      'basePrice': 5.00,
      'pricePerMile': 1.50,
      'image': 'assets/car_standard.png', // Placeholder
    },
    {
      'id': 'executive',
      'name': 'Executive',
      'description': 'Premium rides for business',
      'seats': 4,
      'basePrice': 10.00,
      'pricePerMile': 2.50,
      'image': 'assets/car_exec.png', // Placeholder
    },
    {
      'id': 'xl',
      'name': 'XL',
      'description': 'More space for groups',
      'seats': 6,
      'basePrice': 8.00,
      'pricePerMile': 2.00,
      'image': 'assets/car_xl.png', // Placeholder
    },
  ];
}
