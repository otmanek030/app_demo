import 'package:demo_app/services/DataBackupService%20.dart';
import 'package:flutter/material.dart';
import '../models/version_model.dart';
import '../services/update_service.dart';
import '../utils/constants.dart';

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
  final DataBackupService _dataBackupService = DataBackupService();
  
  bool _downloading = false;
  bool _backingUp = false;
  double _progress = 0;
  String? _error;
  String? _statusMessage;
  int _selectedHours = AppConstants.defaultPostponeHours;
  bool _showDelayOptions = false;

  // Delay options for the user to choose from
  final List<int> _delayOptions = [6, 12, 24, 48];

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
      _backingUp = true;
      _statusMessage = 'Sauvegarde des données...';
      _error = null;
      _progress = 0;
    });
    
    try {
      // First backup user data
      final backupSuccess = await _dataBackupService.backupData(widget.version);
      
      if (!backupSuccess) {
        setState(() {
          _statusMessage = 'Avertissement: La sauvegarde des données a échoué, mais la mise à jour va continuer';
        });
        await Future.delayed(const Duration(seconds: 2));
      }
      
      setState(() {
        _backingUp = false;
        _downloading = true;
        _statusMessage = 'Téléchargement de la mise à jour...';
      });
      
      // Then download and install update
      await _updateService.downloadAndInstallUpdate(
        widget.version,
        (p) => setState(() => _progress = p),
      );
    } catch (e) {
      setState(() => _error = _translateError(e));
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _backingUp = false;
          _statusMessage = null;
        });
      }
    }
  }
  
  Future<void> _postponeUpdate() async {
    setState(() {
      _downloading = true;
    });
    
    try {
      final success = await _updateService.postponeUpdate(
        widget.version,
        hours: _selectedHours,
      );
      
      if (success) {
        widget.onPostpone();
      } else {
        setState(() => _error = 'Échec du report de la mise à jour');
      }
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
    final isDelayed = widget.version.updateType == 'delayed';
    
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
          if (isDelayed && widget.version.isGracePeriodActive) ...[
            Text(
              'Cette mise à jour deviendra obligatoire dans ${widget.version.remainingHours.toStringAsFixed(1)} heures.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
          ],
          if (_showDelayOptions && isDelayed) ...[
            const Text('Reporter la mise à jour de:'),
            const SizedBox(height: 8),
            _buildDelayOptionsSelector(),
            const SizedBox(height: 16),
          ],
          if (_statusMessage != null) ...[
            Text(_statusMessage!, style: TextStyle(fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
          ],
          if (_backingUp) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
          if (_downloading && !_backingUp) ...[
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
            onPressed: (_downloading || _backingUp) ? null : widget.onCancel,
            child: const Text('Ignorer'),
          ),
        if (!isMandatory && isDelayed)
          TextButton(
            onPressed: (_downloading || _backingUp) ? null : () {
              if (_showDelayOptions) {
                _postponeUpdate();
              } else {
                setState(() {
                  _showDelayOptions = true;
                });
              }
            },
            child: Text(_showDelayOptions ? 'Confirmer le report' : 'Plus tard'),
          ),
        ElevatedButton(
          onPressed: (_downloading || _backingUp) ? null : _startUpdate,
          child: (_downloading || _backingUp)
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : const Text('Mettre à jour maintenant'),
        ),
      ],
    );
  }
  
  Widget _buildDelayOptionsSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: _delayOptions.map((hours) {
        // Don't show options that exceed remaining grace period
        if (widget.version.remainingHours > 0 && hours > widget.version.remainingHours) {
          return const SizedBox.shrink();
        }
        
        return ChoiceChip(
          label: Text('$hours h'),
          selected: _selectedHours == hours,
          onSelected: (bool selected) {
            if (selected) {
              setState(() {
                _selectedHours = hours;
              });
            }
          },
        );
      }).toList(),
    );
  }
}