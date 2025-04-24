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
import '../models/version_model.dart';
import '../utils/constants.dart';

class UpdateService {
  static const _channel = MethodChannel('app_channel');

  Future<Map<String, dynamic>> checkForUpdates() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersionCode = int.parse(packageInfo.buildNumber);
    
    final uri = Uri.parse(AppConstants.checkUpdateEndpoint).replace(
      queryParameters: {
        'package_name': AppConstants.packageName,
        'version_code': currentVersionCode.toString(),
      },
    );
    
    debugPrint('Checking for updates at: $uri');
    
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['update_available'] == true && data['version'] != null) {
        final availableVersion = VersionModel.fromJson(data['version']);
        
        // ADD DEBUG PRINTS HERE
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
    final prefs = await SharedPreferences.getInstance();
    
    switch (version.updateType) {
      case 'mandatory':
        return true;
      case 'optional':
        final postponedVersion = prefs.getInt('postponed_version');
        return postponedVersion != version.versionCode;
      case 'delayed':
        final postponedUntil = prefs.getInt('postponed_until');
        return postponedUntil == null || 
               DateTime.now().millisecondsSinceEpoch > postponedUntil;
      default:
        return false;
    }
  }
  
  Future<void> postponeUpdate(VersionModel version) async {
    final prefs = await SharedPreferences.getInstance();
    if (version.updateType == 'delayed') {
      final postponeUntil = DateTime.now().millisecondsSinceEpoch + 
                          (version.gracePeriod * 3600 * 1000);
      await prefs.setInt('postponed_until', postponeUntil);
    } else {
      await prefs.setInt('postponed_version', version.versionCode);
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
    if (!await _checkPermissions()) {
      throw Exception('Permissions not granted');
    }

    final dio = Dio();
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/update_${version.versionCode}.apk';
    
    try {
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
      // Clean up failed download
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
    // Clear postponement data after successful install
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('postponed_version');
    await prefs.remove('postponed_until');
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