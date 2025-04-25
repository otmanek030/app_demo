import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../utils/constants.dart';
import '../models/version_model.dart';

class DataBackupService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  // Get device ID (same as in UpdateService)
  Future<String> getDeviceId() async {
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

  // Register device with server
  Future<bool> registerDevice() async {
    try {
      final deviceId = await getDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.parse(packageInfo.buildNumber);
      
      final androidInfo = await _deviceInfo.androidInfo;
      
      final response = await http.post(
        Uri.parse(AppConstants.registerDeviceEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'device_id': deviceId,
          'model': androidInfo.model,
          'os_version': androidInfo.version.release,
          'current_version': currentVersionCode.toString(),
          'package_name': AppConstants.packageName,
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error registering device: $e');
      return false;
    }
  }

  // Backup app data before update
  Future<bool> backupData(VersionModel version) async {
    try {
      // Get device ID and app data
      final deviceId = await getDeviceId();
      final appData = await _collectAppData();
      
      // Send data to server
      final response = await http.post(
        Uri.parse(AppConstants.dataBackupEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'device_id': deviceId,
          'version_code': version.versionCode,
          'package_name': AppConstants.packageName,
          'json_data': appData,
        }),
      );
      
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Error backing up data: $e');
      return false;
    }
  }

  // Restore app data after update
  Future<Map<String, dynamic>?> restoreData() async {
    try {
      final deviceId = await getDeviceId();
      final packageInfo = await PackageInfo.fromPlatform();
      
      final uri = Uri.parse(AppConstants.dataBackupEndpoint).replace(
        queryParameters: {
          'device_id': deviceId,
          'package_name': AppConstants.packageName,
        },
      );
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['json_data'] != null) {
          // Mark update as completed with data preserved
          await _markUpdateCompleted(int.parse(packageInfo.buildNumber), true);
          return data['json_data'];
        }
      }
      
      // If we couldn't restore data, mark update as completed but with data_preserved=false
      await _markUpdateCompleted(int.parse(packageInfo.buildNumber), false);
      return null;
    } catch (e) {
      debugPrint('Error restoring data: $e');
      return null;
    }
  }

  // Mark update as completed
  Future<bool> _markUpdateCompleted(int versionCode, bool dataPreserved) async {
    try {
      final deviceId = await getDeviceId();
      
      final response = await http.post(
        Uri.parse(AppConstants.updateCompletedEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'device_id': deviceId,
          'version_code': versionCode,
          'package_name': AppConstants.packageName,
          'data_preserved': dataPreserved,
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error marking update as completed: $e');
      return false;
    }
  }

  // Collect app data to back up
  Future<Map<String, dynamic>> _collectAppData() async {
    // This would be replaced with your app's actual data collection logic
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    Map<String, dynamic> data = {};
    for (String key in keys) {
      // Skip keys that should not be backed up
      if (key.startsWith('_internal_') || key == 'ignored_versions') continue;
      
      // Get the value based on its type
      if (prefs.containsKey(key)) {
        if (prefs.getString(key) != null) {
          data[key] = prefs.getString(key);
        } else if (prefs.getBool(key) != null) {
          data[key] = prefs.getBool(key);
        } else if (prefs.getInt(key) != null) {
          data[key] = prefs.getInt(key);
        } else if (prefs.getDouble(key) != null) {
          data[key] = prefs.getDouble(key);
        } else if (prefs.getStringList(key) != null) {
          data[key] = prefs.getStringList(key);
        }
      }
    }
    
    return {
      'preferences': data,
      'app_state': {
        'last_backup_time': DateTime.now().toIso8601String(),
        // Add more app state data here
      }
    };
  }

  // Apply restored data to app
  Future<bool> applyRestoredData(Map<String, dynamic>? data) async {
    if (data == null) return false;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Restore shared preferences
      if (data['preferences'] != null) {
        final preferences = data['preferences'] as Map<String, dynamic>;
        
        for (var entry in preferences.entries) {
          final key = entry.key;
          final value = entry.value;
          
          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is List) {
            await prefs.setStringList(key, value.map((e) => e.toString()).toList());
          }
        }
      }
      
      // Track successful data restoration
      await prefs.setBool('_internal_data_restored', true);
      await prefs.setString('_internal_last_restore_time', DateTime.now().toIso8601String());
      
      return true;
    } catch (e) {
      debugPrint('Error applying restored data: $e');
      return false;
    }
  }

  // Check if this is the first run after an update
  Future<bool> isFirstRunAfterUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.buildNumber;
      
      final lastKnownVersion = prefs.getString('_internal_last_version') ?? '';
      
      if (lastKnownVersion != currentVersion) {
        // Save current version
        await prefs.setString('_internal_last_version', currentVersion);
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('Error checking for first run: $e');
      return false;
    }
  }
}