import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/version_model.dart';
import '../utils/constants.dart';

class UpdateService {
  static const _channel = MethodChannel('app_channel');
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  // Get a unique device identifier to send to the server
  Future<String> _getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown';
      }
      return 'unknown';
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }

  Future<Map<String, dynamic>> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.parse(packageInfo.buildNumber);
      final deviceId = await _getDeviceId();
      
      final uri = Uri.parse(AppConstants.checkUpdateEndpoint).replace(
        queryParameters: {
          'package_name': AppConstants.packageName,
          'version_code': currentVersionCode.toString(),
          'device_id': deviceId,
        },
      );
      
      debugPrint('Checking for updates at: $uri');
      
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Connection timeout');
      });
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Check if the update was postponed by user
        if (data['postponed'] == true) {
          debugPrint('Update was postponed by user, not showing update dialog');
          return {'update_available': false};
        }
        
        if (data['update_available'] == true && data['version'] != null) {
          final availableVersion = VersionModel.fromJson(data['version']);
          
          // ADD DEBUG PRINTS
          debugPrint('Current version code: $currentVersionCode');
          debugPrint('Available version code: ${availableVersion.versionCode}');
          
          // Only show update if available version is newer than current version
          if (availableVersion.versionCode > currentVersionCode) {
            return {
              'update_available': true,
              'version': availableVersion,
            };
          }
        }
        return {'update_available': false};
      } else {
        throw Exception('Failed to check for updates: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return {'update_available': false};
    }
  }
  
  Future<bool> shouldShowUpdate(Map<String, dynamic> updateInfo) async {
    if (!updateInfo['update_available']) return false;
    
    final version = updateInfo['version'] as VersionModel;
    
    switch (version.updateType) {
      case 'mandatory':
        return true;
      case 'optional':
        final prefs = await SharedPreferences.getInstance();
        final ignoredVersions = prefs.getStringList('ignored_versions') ?? [];
        return !ignoredVersions.contains(version.versionCode.toString());
      case 'delayed':
        // The server is already handling postponed updates via device_id
        return true;
      default:
        return false;
    }
  }
  
  Future<bool> postponeUpdate(VersionModel version, {int? hours}) async {
    try {
      final deviceId = await _getDeviceId();
      final hoursToPostpone = hours ?? AppConstants.defaultPostponeHours;
      
      // For optional updates, just store locally
      if (version.updateType == 'optional') {
        final prefs = await SharedPreferences.getInstance();
        final ignoredVersions = prefs.getStringList('ignored_versions') ?? [];
        if (!ignoredVersions.contains(version.versionCode.toString())) {
          ignoredVersions.add(version.versionCode.toString());
          await prefs.setStringList('ignored_versions', ignoredVersions);
        }
        return true;
      }
      
      // For delayed updates, use the server API
      if (version.updateType == 'delayed') {
        final response = await http.post(
          Uri.parse(AppConstants.postponeUpdateEndpoint),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'package_name': AppConstants.packageName,
            'version_code': version.versionCode,
            'device_id': deviceId,
            'hours': hoursToPostpone,
          }),
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          debugPrint('Update postponed successfully: ${data['actual_hours']} hours');
          return true;
        } else {
          debugPrint('Failed to postpone update: ${response.statusCode}');
          return false;
        }
      }
      
      return false;
    } catch (e) {
      debugPrint('Error postponing update: $e');
      return false;
    }
  }

  Future<bool> checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) return false;

      // For Android 10 and below
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isDenied) {
        await Permission.storage.request();
      }
      
      return status.isGranted;
    }
    return true;
  }

  Future<void> downloadAndInstallUpdate(
      VersionModel version,
      Function(double) onProgressUpdate,
    ) async {
      // Basic implementation without compute
      if (!await _checkPermissions()) {
        throw Exception('Permissions not granted');
      }

      final dio = Dio();
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/update_${version.versionCode}.apk';
      
      try {
        // Directly do the download without compute
        await dio.download(
          version.apkUrl,
          savePath,
          onReceiveProgress: (received, total) {
            if (total != -1) onProgressUpdate(received / total);
          },
        );

        await _installApk(savePath);
      } catch (e) {
        print('Update error: $e');
        try { await File(savePath).delete(); } catch (_) {}
        rethrow;
      }
    }

  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> _installApk(String apkPath) async {
    try {
      await _channel.invokeMethod('installApk', {'filePath': apkPath});
      // Clear local ignored versions after successful install
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('ignored_versions');
    } on PlatformException catch (e) {
      print('Install error: ${e.message}');
      await _launchApkInstaller(apkPath);
    }
  }

  Future<void> _launchApkInstaller(String apkPath) async {
    final file = File(apkPath);
    if (await file.exists()) {
      await OpenFile.open(apkPath);
    } else {
      throw Exception('APK file not found');
    }
  }

  Future<void> testMethodChannel() async {
    try {
      final result = await _channel.invokeMethod<String>('echo', 'Hello from Flutter');
      print('Method channel test result: $result');
    } on PlatformException catch (e) {
      print('Method channel test error: ${e.message}');
    }
  }
}