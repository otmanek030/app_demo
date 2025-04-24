import 'package:flutter/material.dart';
import '../models/version_model.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final VersionModel version;
  final VoidCallback onCancel;
  final VoidCallback onPostpone;
  
  const UpdateDialog({
    Key? key,
    required this.version,
    required this.onCancel,
    required this.onPostpone,
  }) : super(key: key);
  
  @override
  _UpdateDialogState createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateService _updateService = UpdateService();
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  String _translateError(dynamic error) {
    final message = error.toString();
    if (message.contains('Permission')) {
      return 'Autorisation requise: Activez l\'installation depuis des sources inconnues dans les paramètres';
    }
    if (message.contains('FileProvider')) {
      return 'Erreur de configuration technique. Contactez le support.';
    }
    return 'Échec de la mise à jour: ${message.split(':').first}';
  }

  Future<void> _startUpdate() async {
    if (_downloading) return;
    
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    
    try {
      await _updateService.downloadAndInstallUpdate(
        widget.version,
        (p) => setState(() => _progress = p),
      );
    } catch (e) {
      setState(() => _error = _translateError(e));
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isMandatory = widget.version.updateType == 'mandatory';
    
    return AlertDialog(
      title: const Text('Mise à jour disponible'),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${widget.version.versionName}', 
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
            if (widget.version.releaseNotes.isNotEmpty) ...[
            const Text('Notes de version:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(widget.version.releaseNotes),
              const SizedBox(height: 16),
            ],
            if (_downloading) ...[
            LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
            Text('${(_progress * 100).toStringAsFixed(0)}% téléchargé'),
            const SizedBox(height: 16),
            ],
          if (_error != null) ...[
            Text(_error!, 
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (!isMandatory) 
          TextButton(
            onPressed: _downloading ? null : widget.onCancel,
            child: const Text('Ignorer'),
          ),
        if (!isMandatory && widget.version.updateType == 'delayed')
          TextButton(
            onPressed: _downloading ? null : widget.onPostpone,
            child: const Text('Plus tard'),
          ),
        ElevatedButton(
          onPressed: _downloading ? null : _startUpdate,
          child: _downloading
              ? const CircularProgressIndicator()
              : const Text('Mettre à jour maintenant'),
        ),
      ],
    );
  }
}