import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';

class CropEditor extends StatefulWidget {
  const CropEditor({super.key});

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  double _cropLeft = 0.0;
  double _cropTop = 0.0;
  double _cropRight = 1.0;
  double _cropBottom = 1.0;
  bool _isAspectRatioLocked = false;
  double _aspectRatio = 16 / 9;

  @override
  void initState() {
    super.initState();
    _loadCurrentCropSettings();
  }

  void _loadCurrentCropSettings() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;
    
    if (selectedClipId != null && provider.currentProject != null) {
      final clip = provider.currentProject!.videoClips
          .firstWhere((c) => c.id == selectedClipId);
      
      if (clip.cropRect != null) {
        setState(() {
          _cropLeft = clip.cropRect!.left;
          _cropTop = clip.cropRect!.top;
          _cropRight = clip.cropRect!.right;
          _cropBottom = clip.cropRect!.bottom;
        });
      }
    }
  }

  void _applyCrop() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final selectedClipId = provider.selectedVideoClipId;
    
    if (selectedClipId != null) {
      final cropRect = Rect.fromLTRB(_cropLeft, _cropTop, _cropRight, _cropBottom);
      provider.cropVideoClip(selectedClipId, cropRect);
    }
  }

  void _resetCrop() {
    setState(() {
      _cropLeft = 0.0;
      _cropTop = 0.0;
      _cropRight = 1.0;
      _cropBottom = 1.0;
    });
    _applyCrop();
  }

  void _setAspectRatio(double ratio) {
    setState(() {
      _aspectRatio = ratio;
      _isAspectRatioLocked = true;
      
      // Adjust crop to maintain aspect ratio
      final currentWidth = _cropRight - _cropLeft;
      final currentHeight = _cropBottom - _cropTop;
      final currentRatio = currentWidth / currentHeight;
      
      if (currentRatio > ratio) {
        // Too wide, adjust width
        final newWidth = currentHeight * ratio;
        final centerX = (_cropLeft + _cropRight) / 2;
        _cropLeft = (centerX - newWidth / 2).clamp(0.0, 1.0);
        _cropRight = (centerX + newWidth / 2).clamp(0.0, 1.0);
      } else {
        // Too tall, adjust height
        final newHeight = currentWidth / ratio;
        final centerY = (_cropTop + _cropBottom) / 2;
        _cropTop = (centerY - newHeight / 2).clamp(0.0, 1.0);
        _cropBottom = (centerY + newHeight / 2).clamp(0.0, 1.0);
      }
    });
    _applyCrop();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final selectedClipId = provider.selectedVideoClipId;

        // If no selection, auto-select the clip under playhead or the first clip
        if (selectedClipId == null) {
          final autoClip = provider.currentVideoClip ??
              (provider.currentProject?.videoClips.isNotEmpty == true
                  ? provider.currentProject!.videoClips.first
                  : null);
          if (autoClip != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              provider.selectVideoClip(autoClip.id);
            });
          }
          return const Center(
            child: Text(
              'Select a video clip to crop',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        // Ensure local state mirrors the selected clip's current crop
        final clip = provider.currentProject!.videoClips.firstWhere((c) => c.id == selectedClipId);
        final clipCrop = clip.cropRect ?? const Rect.fromLTWH(0, 0, 1, 1);
        // Update local values only if different to prevent rebuild loops
        if ((_cropLeft - clipCrop.left).abs() > 0.0001 ||
            (_cropTop - clipCrop.top).abs() > 0.0001 ||
            (_cropRight - clipCrop.right).abs() > 0.0001 ||
            (_cropBottom - clipCrop.bottom).abs() > 0.0001) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _cropLeft = clipCrop.left;
              _cropTop = clipCrop.top;
              _cropRight = clipCrop.right;
              _cropBottom = clipCrop.bottom;
            });
          });
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
                    const Icon(Icons.crop, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Crop Video',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      onPressed: _resetCrop,
                      tooltip: 'Reset Crop',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Aspect Ratio Presets
                const Text(
                  'Aspect Ratio Presets',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildAspectRatioButton('Free', null),
                    _buildAspectRatioButton('16:9', 16/9),
                    _buildAspectRatioButton('4:3', 4/3),
                    _buildAspectRatioButton('1:1', 1.0),
                    _buildAspectRatioButton('9:16', 9/16),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Crop Controls
                Column(
                  children: [
                    _buildCropSlider('Left', _cropLeft, (value) {
                      setState(() {
                        _cropLeft = value.clamp(0.0, _cropRight - 0.1);
                      });
                      _applyCrop();
                    }),
                    _buildCropSlider('Top', _cropTop, (value) {
                      setState(() {
                        _cropTop = value.clamp(0.0, _cropBottom - 0.1);
                      });
                      _applyCrop();
                    }),
                    _buildCropSlider('Right', _cropRight, (value) {
                      setState(() {
                        _cropRight = value.clamp(_cropLeft + 0.1, 1.0);
                      });
                      _applyCrop();
                    }),
                    _buildCropSlider('Bottom', _cropBottom, (value) {
                      setState(() {
                        _cropBottom = value.clamp(_cropTop + 0.1, 1.0);
                      });
                      _applyCrop();
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Crop Info
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crop Area: ${((_cropRight - _cropLeft) * 100).toInt()}% × ${((_cropBottom - _cropTop) * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Position: ${(_cropLeft * 100).toInt()}%, ${(_cropTop * 100).toInt()}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
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

  Widget _buildAspectRatioButton(String label, double? ratio) {
    final isSelected = ratio == null ? !_isAspectRatioLocked : 
                     _isAspectRatioLocked && (_aspectRatio - (ratio)).abs() < 0.01;
    
    return ElevatedButton(
      onPressed: () {
        if (ratio == null) {
          setState(() {
            _isAspectRatioLocked = false;
          });
        } else {
          _setAspectRatio(ratio);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.purple : Colors.grey[700],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 28),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }

  Widget _buildCropSlider(String label, double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              onChanged: onChanged,
              activeColor: Colors.purple,
              inactiveColor: Colors.grey,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${(value * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 10),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
