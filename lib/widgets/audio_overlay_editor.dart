import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';

class AudioOverlayEditor extends StatefulWidget {
  const AudioOverlayEditor({super.key});

  @override
  State<AudioOverlayEditor> createState() => _AudioOverlayEditorState();
}

class _AudioOverlayEditorState extends State<AudioOverlayEditor> {
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();
  
  File? _selectedAudioFile;
  double _volume = 1.0;
  Duration _audioStartOffset = Duration.zero;
  bool _fadeIn = false;
  bool _fadeOut = false;

  @override
  void dispose() {
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        // Update fields if an audio overlay is selected
        if (provider.selectedAudioOverlayId != null) {
          final overlay = provider.currentProject!.audioOverlays
              .firstWhere((o) => o.id == provider.selectedAudioOverlayId);
          _updateFieldsFromOverlay(overlay);
        }

        // Default start/end to playhead when fields are empty or not set by selection
        final projectEnd = provider.projectDuration;
        final playhead = provider.currentPosition;
        if (_startTimeController.text.isEmpty) {
          _startTimeController.text = _formatDuration(playhead);
        }
        if (_endTimeController.text.isEmpty) {
          final tentativeEnd = playhead + const Duration(seconds: 10);
          final clampedEnd = tentativeEnd > projectEnd ? projectEnd : tentativeEnd;
          _endTimeController.text = _formatDuration(clampedEnd);
        }

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(provider),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;
                  Widget content;

                  if (isNarrow) {
                    // Stack vertically on narrow widths
                    content = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAudioSelector(provider),
                        const SizedBox(height: 16),
                        _buildAudioSettings(provider),
                      ],
                    );
                  } else {
                    // Side-by-side on wider widths
                    content = Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Use Flexible to avoid tight constraints inside scrollables
                        Flexible(
                          flex: 2,
                          child: _buildAudioSelector(provider),
                        ),
                        const SizedBox(width: 16),
                        // Give right panel a reasonable width
                        SizedBox(
                          width: constraints.maxWidth * 0.33,
                          child: _buildAudioSettings(provider),
                        ),
                      ],
                    );
                  }

                    return SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.zero,
                      child: content,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(VideoEditorProvider provider) {
    return Row(
      children: [
        const Text(
          'Audio Overlay Editor',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (provider.selectedAudioOverlayId != null)
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteSelectedOverlay(provider),
            tooltip: 'Delete Audio Overlay',
          ),
        if (provider.selectedAudioOverlayId != null)
          ElevatedButton.icon(
            onPressed: () => _updateSelectedOverlay(provider),
            icon: const Icon(Icons.save),
            label: const Text('Update'),
          ),
      ],
    );
  }

  Widget _buildAudioSelector(VideoEditorProvider provider) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audio File',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[600]!),
              ),
              child: _selectedAudioFile != null
                  ? _buildAudioFileInfo()
                  : _buildAudioFilePicker(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Start Time',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _startTimeController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: '00:00',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.purple),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'End Time',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _endTimeController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: '00:10',
                          hintStyle: TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.purple),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAudioOffsetSlider(),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioFileInfo() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.audiotrack,
          size: 48,
          color: Colors.orange,
        ),
        const SizedBox(height: 8),
        Text(
          _selectedAudioFile!.path.split('/').last,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _selectAudioFile,
              child: const Text('Change File'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedAudioFile = null;
                });
              },
              child: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioFilePicker() {
    return InkWell(
      onTap: _selectAudioFile,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_upload,
            size: 48,
            color: Colors.grey,
          ),
          SizedBox(height: 8),
          Text(
            'Tap to select audio file',
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 4),
          Text(
            'Supported: MP3, WAV, AAC, M4A',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioOffsetSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Audio Start Offset: ${_formatDuration(_audioStartOffset)}',
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Slider(
          value: _audioStartOffset.inSeconds.toDouble(),
          min: 0,
          max: 60, // Max 1 minute offset
          divisions: 60,
          onChanged: (value) {
            setState(() {
              _audioStartOffset = Duration(seconds: value.toInt());
            });
          },
          activeColor: Colors.orange,
        ),
      ],
    );
  }

  Widget _buildAudioSettings(VideoEditorProvider provider) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audio Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildVolumeSlider(),
            const SizedBox(height: 16),
            _buildFadeControls(),
            const SizedBox(height: 24),
            _buildAudioPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Volume: ${(_volume * 100).toInt()}%',
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.volume_down, color: Colors.white, size: 20),
            Expanded(
              child: Slider(
                value: _volume,
                min: 0.0,
                max: 2.0, // Allow up to 200% volume
                divisions: 40,
                onChanged: (value) {
                  setState(() {
                    _volume = value;
                  });
                },
                activeColor: Colors.orange,
              ),
            ),
            const Icon(Icons.volume_up, color: Colors.white, size: 20),
          ],
        ),
      ],
    );
  }

  Widget _buildFadeControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fade Effects',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                title: const Text(
                  'Fade In',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                value: _fadeIn,
                onChanged: (value) {
                  setState(() {
                    _fadeIn = value ?? false;
                  });
                },
                activeColor: Colors.orange,
                checkColor: Colors.white,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                title: const Text(
                  'Fade Out',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                value: _fadeOut,
                onChanged: (value) {
                  setState(() {
                    _fadeOut = value ?? false;
                  });
                },
                activeColor: Colors.orange,
                checkColor: Colors.white,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preview',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey),
          ),
          child: _selectedAudioFile != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.audiotrack,
                      color: Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Volume: ${(_volume * 100).toInt()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    if (_fadeIn || _fadeOut)
                      Text(
                        '${_fadeIn ? 'Fade In' : ''}${_fadeIn && _fadeOut ? ' + ' : ''}${_fadeOut ? 'Fade Out' : ''}',
                        style: const TextStyle(color: Colors.orange, fontSize: 10),
                      ),
                  ],
                )
              : const Center(
                  child: Text(
                    'No audio file selected',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _selectAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        // Determine audio duration using just_audio so we can place full-length overlay
        Duration? audioDuration;
        final tmpPlayer = AudioPlayer();
        try {
          await tmpPlayer.setFilePath(file.path);
          // Wait for duration to be available
          audioDuration = tmpPlayer.duration;
        } catch (_) {
          audioDuration = null;
        } finally {
          await tmpPlayer.dispose();
        }

        final provider = Provider.of<VideoEditorProvider>(context, listen: false);
        final start = provider.currentPosition;
        // If duration known, end = start + audioDuration; else fallback 5 minutes
        final overlayDur = audioDuration ?? const Duration(minutes: 5);
        final end = start + overlayDur;

        await provider.addAudioOverlay(
          audioFile: file,
          startTime: start,
          endTime: end,
          audioStartOffset: Duration.zero,
          volume: 1.0,
          fadeIn: false,
          fadeOut: false,
        );

        // Clear and close editor
        _clearFields();
        provider.toggleTimeline();
      }
    } catch (e) {
      _showErrorDialog('Failed to select audio file: $e');
    }
  }

  void _updateFieldsFromOverlay(AudioOverlay overlay) {
    _selectedAudioFile = overlay.audioFile;
    _volume = overlay.volume;
    _audioStartOffset = overlay.audioStartOffset;
    _fadeIn = overlay.fadeIn;
    _fadeOut = overlay.fadeOut;
    
    _startTimeController.text = _formatDuration(overlay.startTime);
    _endTimeController.text = _formatDuration(overlay.endTime);
  }

  Future<void> _addAudioOverlay(VideoEditorProvider provider) async {
    if (_selectedAudioFile == null) {
      _showErrorDialog('Please select an audio file');
      return;
    }

    final startTime = _parseDuration(_startTimeController.text);
    final endTime = _parseDuration(_endTimeController.text);

    if (startTime >= endTime) {
      _showErrorDialog('End time must be after start time');
      return;
    }

    await provider.addAudioOverlay(
      audioFile: _selectedAudioFile!,
      startTime: startTime,
      endTime: endTime,
      audioStartOffset: _audioStartOffset,
      volume: _volume,
      fadeIn: _fadeIn,
      fadeOut: _fadeOut,
    );

    _clearFields();
  }

  Future<void> _updateSelectedOverlay(VideoEditorProvider provider) async {
    final overlayId = provider.selectedAudioOverlayId;
    if (overlayId == null) return;

    final startTime = _parseDuration(_startTimeController.text);
    final endTime = _parseDuration(_endTimeController.text);

    if (startTime >= endTime) {
      _showErrorDialog('End time must be after start time');
      return;
    }

    await provider.updateAudioOverlay(
      overlayId,
      startTime: startTime,
      endTime: endTime,
      audioStartOffset: _audioStartOffset,
      volume: _volume,
      fadeIn: _fadeIn,
      fadeOut: _fadeOut,
    );
  }

  Future<void> _deleteSelectedOverlay(VideoEditorProvider provider) async {
    if (provider.selectedAudioOverlayId != null) {
      await provider.removeAudioOverlay(provider.selectedAudioOverlayId!);
      _clearFields();
    }
  }

  void _clearFields() {
    _startTimeController.text = '';
    _endTimeController.text = '';
    setState(() {
      _selectedAudioFile = null;
      _volume = 1.0;
      _audioStartOffset = Duration.zero;
      _fadeIn = false;
      _fadeOut = false;
    });
  }

  Duration _parseDuration(String timeString) {
    final parts = timeString.split(':');
    if (parts.length != 2) return Duration.zero;
    
    final minutes = int.tryParse(parts[0]) ?? 0;
    final seconds = int.tryParse(parts[1]) ?? 0;
    
    return Duration(minutes: minutes, seconds: seconds);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
