class ApiConstants {
  static const String baseUrl = 'http://192.168.1.7:5000'; // TODO: Replace with actual base URL

  // Auth Endpoints
  static const String sendOtp = '$baseUrl/auth/send-otp';
  static const String verifyOtp = '$baseUrl/auth/verify-otp';
  
  // User Endpoints
  static const String userRegister = '$baseUrl/user/register';
  static const String userLogin = '$baseUrl/user/login';

  // Driver Endpoints
  static const String driverRegister = '$baseUrl/driver/register';
  static const String driverLogin = '$baseUrl/driver/login';
}
