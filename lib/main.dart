import 'package:demo_app/services/DataBackupService%20.dart';
import 'package:flutter/material.dart';
import 'package:demo_app/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/version_model.dart';
import 'services/update_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Demo App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final UpdateService _updateService = UpdateService();
  final DataBackupService _dataBackupService = DataBackupService();
  
  bool _isLoading = true;
  String _appVersion = '';
  Map<String, dynamic>? _restoredData;
  bool _dataRestored = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    setState(() => _isLoading = true);
    
    // Register device with server
    await _dataBackupService.registerDevice();
    
    // Get app version
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    
    // Check if this is first run after update
    final isFirstRun = await _dataBackupService.isFirstRunAfterUpdate();
    
    if (isFirstRun) {
      // Try to restore data
      final restoredData = await _dataBackupService.restoreData();
      
      if (restoredData != null) {
        // Apply restored data
        final success = await _dataBackupService.applyRestoredData(restoredData);
        
        if (success) {
          setState(() {
            _restoredData = restoredData;
            _dataRestored = true;
          });
        }
      }
    }
    
    // Check for updates
    await _checkForUpdates();
    
    setState(() => _isLoading = false);
  }

  Future<void> _checkForUpdates() async {
    // Delay a bit to allow the app to fully initialize
    await Future.delayed(const Duration(seconds: 2));
    final updateInfo = await _updateService.checkForUpdates();
    final shouldShow = await _updateService.shouldShowUpdate(updateInfo);
    
    if (shouldShow && updateInfo['update_available'] && mounted) {
      _showUpdateDialog(updateInfo['version']);
    }
  }

  void _showUpdateDialog(VersionModel version) {
    showDialog(
      context: context,
      barrierDismissible: version.updateType != 'mandatory',
      builder: (context) => PopScope(
        // Prevent back button from dismissing mandatory updates
        canPop: version.updateType != 'mandatory',
        child: UpdateDialog(
          version: version,
          onCancel: () {
            Navigator.of(context).pop();
          },
          onPostpone: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  // Example method to save some data that will be backed up
  Future<void> _saveTestData() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString('last_saved_time', now.toIso8601String());
    await prefs.setString('test_data', 'This is some test data saved at $now');
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test data saved successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My App'),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('App Version: $_appVersion', 
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    
                    if (_dataRestored) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(height: 8),
                            Text(
                              'Données restaurées avec succès après la mise à jour!',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    ElevatedButton(
                      onPressed: _checkForUpdates,
                      child: const Text('Vérifier les mises à jour'),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    ElevatedButton(
                      onPressed: _saveTestData,
                      child: const Text('Sauvegarder des données de test'),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Show sample of restored data if available
                    if (_restoredData != null) ...[
                      const Text('Aperçu des données restaurées:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_restoredData!['preferences'] != null &&
                                _restoredData!['preferences']['last_saved_time'] != null) ...[
                              Text('Dernière sauvegarde: ${_restoredData!['preferences']['last_saved_time']}'),
                              const SizedBox(height: 4),
                            ],
                            if (_restoredData!['preferences'] != null &&
                                _restoredData!['preferences']['test_data'] != null) ...[
                              Text('Données: ${_restoredData!['preferences']['test_data']}'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}