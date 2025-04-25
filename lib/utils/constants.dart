class AppConstants {
  // URL de l'API
  static const String baseUrl = 'http://192.168.100.91:8000/api';
  
  static const String checkUpdateEndpoint = '$baseUrl/check-update/';
  static const String postponeUpdateEndpoint = '$baseUrl/postpone-update/';
  static const String registerDeviceEndpoint = '$baseUrl/register-device/';
  static const String dataBackupEndpoint = '$baseUrl/data-backup/';
  static const String updateCompletedEndpoint = '$baseUrl/update-completed/';
  
  static const String packageName = 'com.example.demo_app';
  
  // Default delay time in hours when user clicks "Plus tard"
  static const int defaultPostponeHours = 24;
}