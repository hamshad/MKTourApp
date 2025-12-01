class ApiConstants {
  static const String baseUrl = 'http://192.168.1.16:5000'; // TODO: Replace with actual base URL

  // Auth Endpoints
  static const String sendOtp = '$baseUrl/auth/send-otp';
  static const String verifyOtp = '$baseUrl/auth/verify-otp';
  
  // User Endpoints
  static const String userRegister = '$baseUrl/user/register';
  static const String userLogin = '$baseUrl/user/login';
  static const String userProfile = '$baseUrl/users/me';

  // Driver Endpoints
  static const String driverRegister = '$baseUrl/driver/register';
  static const String driverLogin = '$baseUrl/driver/login';
  static const String driverProfile = '$baseUrl/drivers/me';
  static const String uploadVehicleImages = '$baseUrl/drivers/upload-vehicle-images';
  static const String deleteVehicleImage = '$baseUrl/drivers/delete-vehicle-image';
  static const String uploadLicense = '$baseUrl/drivers/upload-license';
  static const String updateDriverStatus = '$baseUrl/drivers/status';
  static const String updateDriver = '$baseUrl/drivers/update';

  // Ride Endpoints
  static const String createRide = '$baseUrl/rides/create';
  static String getRideDetails(String id) => '$baseUrl/rides/$id';
}
