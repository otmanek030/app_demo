// lib/main.dart
import 'package:flutter/material.dart';
import 'models/version_model.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'what changes in this version',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final UpdateService _updateService = UpdateService();
  bool _checkingForUpdates = false;
  String? _status;
  
  @override
  void initState() {
    super.initState();
    // Vérifier les mises à jour au démarrage
    Future.delayed(const Duration(seconds: 1), () {
      _checkForUpdates(silent: true);
    });
  }
  
  Future<void> _checkForUpdates({bool silent = false}) async {
    if (_checkingForUpdates) return;
    
    setState(() {
      _checkingForUpdates = true;
      if (!silent) _status = 'Vérification des mises à jour...';
    });
    
    try {
      final updateInfo = await _updateService.checkForUpdates();
      final shouldShow = await _updateService.shouldShowUpdate(updateInfo);
      
      if (shouldShow) {
        _showUpdateDialog(updateInfo['version']);
      } else if (!silent) {
        setState(() {
          _status = 'Aucune mise à jour disponible';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _status = null;
            });
          }
        });
      }
    } catch (e) {
      if (!silent) {
        setState(() {
          _status = 'Erreur: $e';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _status = null;
            });
          }
        });
      }
    } finally {
      setState(() {
        _checkingForUpdates = false;
      });
    }
  }
  
  void _showUpdateDialog(VersionModel version) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: version.updateType != 'mandatory',
      builder: (context) => UpdateDialog(
        version: version,
        onCancel: () {
          Navigator.of(context).pop();
        },
        onPostpone: () async {
          await _updateService.postponeUpdate(version);
          Navigator.of(context).pop();
        },
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('my app '),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'hello',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 40),
            if (_status != null) ...[
              Text(_status!, style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 20),
            ],
            ElevatedButton(
              onPressed: _checkingForUpdates ? null : () => _checkForUpdates(),
              child: _checkingForUpdates 
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Vérifier'),
            ),
          ],
        ),
      ),
    );
  }
}