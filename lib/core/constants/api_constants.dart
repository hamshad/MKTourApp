class ApiConstants {
  static const String baseUrl =
      'http://192.168.1.12:5000/api/v1'; // TODO: Replace with actual base URL
  // static const String baseUrl = 'https://api.mktours.co.uk';
  static const String socketUrl =
      'http://192.168.1.12:5000/'; // TODO: Replace with actual base URL
  // static const String socketUrl = 'https://api.mktours.co.uk';

  // Auth Endpoints
  static const String sendOtp = '$baseUrl/auth/send-otp';
  static const String verifyOtp = '$baseUrl/auth/verify-otp';

  // User Endpoints
  static const String userRegister = '$baseUrl/user/register';
  static const String userLogin = '$baseUrl/user/login';
  static const String userProfile = '$baseUrl/users/me';
  static const String updateUser = '$baseUrl/users/update';
  static const String rideHistory = '$baseUrl/users/rides';

  // Driver Endpoints
  static const String driverRegister = '$baseUrl/driver/register';
  static const String driverLogin = '$baseUrl/driver/login';
  static const String driverProfile = '$baseUrl/drivers/me';
  static const String uploadVehicleImages =
      '$baseUrl/drivers/upload-vehicle-images';
  static const String deleteVehicleImage =
      '$baseUrl/drivers/delete-vehicle-image';
  static const String uploadLicense = '$baseUrl/drivers/upload-license';
  static const String updateDriverStatus = '$baseUrl/drivers/status';
  static const String updateDriver = '$baseUrl/drivers/update';
  static const String updateDriverLocation = '$baseUrl/drivers/location';
  static const String driverProfileStatus = '$baseUrl/drivers/profile-status';

  // Ride Endpoints
  static const String createRide = '$baseUrl/rides/create';
  static String getRideDetails(String id) => '$baseUrl/rides/$id';
  static String acceptRide(String id) => '$baseUrl/rides/$id/accept';
  static String startRide(String id) => '$baseUrl/rides/$id/start';
  static String completeRide(String id) => '$baseUrl/rides/$id/complete';
  static String cancelRide(String id) => '$baseUrl/rides/$id/cancel';
  static String arriveAtPickup(String id) => '$baseUrl/rides/$id/arrive';

  // User cancellation endpoint (before ride starts)
  static String cancelRideByUser(String id) => '$baseUrl/rides/$id/cancel/user';

  // Driver cancellation endpoint (before ride starts)
  static String cancelRideByDriver(String id) =>
      '$baseUrl/rides/$id/cancel/driver';

  // End ride early endpoint (driver only, during ride)
  static String endRideEarly(String id) => '$baseUrl/rides/$id/end-early';

  // Maps API Endpoints (proxied through backend for security)
  static const String mapsBaseUrl = '$baseUrl/maps';
  static const String getSuggestions = '$mapsBaseUrl/get-suggestions';
  static const String placeDetails = '$mapsBaseUrl/place-details';
  static const String reverseGeocode = '$mapsBaseUrl/reverse-geocode';
  static const String getDistanceTime = '$mapsBaseUrl/get-distance-time';
  static const String getDirections = '$mapsBaseUrl/get-directions';
}
