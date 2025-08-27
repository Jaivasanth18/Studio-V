import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';

class RotateEditor extends StatefulWidget {
  const RotateEditor({super.key});

  @override
  State<RotateEditor> createState() => _RotateEditorState();
}

class _RotateEditorState extends State<RotateEditor> {
  double _currentRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCurrentRotation();
  }

  void _loadCurrentRotation() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;
    
    if (selectedClipId != null && provider.currentProject != null) {
      final clip = provider.currentProject!.videoClips
          .firstWhere((c) => c.id == selectedClipId);
      
      setState(() {
        _currentRotation = clip.rotation;
      });
    }
  }

  void _applyRotation(double rotation) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;
    
    if (selectedClipId != null) {
      provider.rotateVideoClip(selectedClipId, rotation);
    }
  }

  void _rotateBy90Degrees(bool clockwise) {
    final newRotation = clockwise 
        ? (_currentRotation + 90) % 360
        : (_currentRotation - 90) % 360;
    
    setState(() {
      _currentRotation = newRotation;
    });
    _applyRotation(_currentRotation);
  }

  void _resetRotation() {
    setState(() {
      _currentRotation = 0.0;
    });
    _applyRotation(0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final selectedClipId = provider.selectedVideoClipId;
        
        if (selectedClipId == null) {
          return const Center(
            child: Text(
              'Select a video clip to rotate',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.rotate_right, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Rotate Video',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      onPressed: _resetRotation,
                      tooltip: 'Reset Rotation',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Quick Rotation Buttons
                const Text(
                  'Quick Rotate',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildQuickRotateButton(
                      'Rotate Left 90°',
                      Icons.rotate_left,
                      () => _rotateBy90Degrees(false),
                    ),
                    _buildQuickRotateButton(
                      'Rotate Right 90°',
                      Icons.rotate_right,
                      () => _rotateBy90Degrees(true),
                    ),
                    _buildQuickRotateButton(
                      'Flip 180°',
                      Icons.flip,
                      () {
                        setState(() {
                          _currentRotation = (_currentRotation + 180) % 360;
                        });
                        _applyRotation(_currentRotation);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Fine Rotation Control
                const Text(
                  'Fine Rotation',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(
                      width: 50,
                      child: Text(
                        'Angle',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _currentRotation,
                        min: 0.0,
                        max: 360.0,
                        divisions: 360,
                        onChanged: (value) {
                          setState(() {
                            _currentRotation = value;
                          });
                        },
                        onChangeEnd: (value) {
                          _applyRotation(value);
                        },
                        activeColor: Colors.purple,
                        inactiveColor: Colors.grey,
                      ),
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${_currentRotation.toInt()}°',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Rotation Preview
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      // Visual rotation indicator
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Transform.rotate(
                          angle: _currentRotation * (3.14159 / 180),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Rotation: ${_currentRotation.toInt()}°',
                              style: const TextStyle(color: Colors.white, fontSize: 11),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getRotationDescription(_currentRotation),
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickRotateButton(String tooltip, IconData icon, VoidCallback onPressed) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: const Size(0, 36),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(height: 2),
              Text(
                tooltip.split(' ').last,
                style: const TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRotationDescription(double rotation) {
    final normalizedRotation = rotation % 360;
    if (normalizedRotation == 0) return 'Original orientation';
    if (normalizedRotation == 90) return 'Rotated 90° clockwise';
    if (normalizedRotation == 180) return 'Upside down';
    if (normalizedRotation == 270) return 'Rotated 90° counter-clockwise';
    return 'Custom rotation: ${normalizedRotation.toInt()}°';
  }
}
