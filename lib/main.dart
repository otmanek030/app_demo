import 'package:flutter/material.dart';
import 'package:demo_app/widgets/update_dialog.dart';
import 'models/version_model.dart';
import 'services/update_service.dart';

void main() {
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

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('App Content'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkForUpdates,
              child: const Text('Check for Updates'),
            ),
          ],
        ),
      ),
    );
  }
}