import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_editor/video_editor.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/video_editor_provider.dart';
import '../services/permissions_service.dart';
import '../widgets/timeline_widget.dart';
import '../widgets/text_overlay_editor.dart';
import '../widgets/audio_overlay_editor.dart';
import '../widgets/filter_editor.dart';
import '../widgets/crop_editor.dart';
import '../widgets/rotate_editor.dart';
import '../models/video_project.dart';

// Clipper to crop a rectangular area (top-level)
class _RectClipper extends CustomClipper<Path> {
  final Rect rect;
  _RectClipper(this.rect);

  @override
  Path getClip(Size size) {
    return Path()..addRect(rect);
  }

  @override
  bool shouldReclip(covariant _RectClipper oldClipper) {
    return oldClipper.rect != rect;
  }
}

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final PermissionsService _permissionsService = PermissionsService();
  bool _permissionsGranted = false;
  // Key to get RenderBox of the preview Stack for accurate drag drop mapping
  final GlobalKey _previewStackKey = GlobalKey();
  // Store finger-to-topLeft offset for each text overlay during drag
  final Map<String, Offset> _textDragOffsets = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final hasPermissions = await _permissionsService.hasAllRequiredPermissions();
    setState(() {
      _permissionsGranted = hasPermissions;
    });

    // Only show dialog if permissions are not granted
    if (!hasPermissions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPermissionsDialog();
      });
    }
  }

  Future<void> _showPermissionsDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Storage Permission Required'),
        content: const Text(
          'This app needs access to your device storage to import and save videos. Please grant storage permission to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Grant Permissions'),
          ),
        ],
      ),
    );

    if (result == true) {
      // Request only minimal (storage/photos) permissions at app start
      final permissions = await _permissionsService.requestBasicPermissions();
      final storageGranted = permissions['storage'] ?? false;
      
      setState(() {
        _permissionsGranted = storageGranted;
      });

      if (!storageGranted) {
        _showPermissionsDeniedDialog(permissions);
      }
    }
  }

  void _showPermissionsDeniedDialog(Map<String, bool> permissions) {
    final denied = permissions.entries
        .where((entry) => !entry.value)
        .map((entry) => _permissionsService.getPermissionDisplayName(entry.key))
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Denied'),
        content: Text(
          'The following permissions were denied: ${denied.join(', ')}.\n\n'
          'Some features may not work properly. You can grant permissions manually in the app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _permissionsService.openAppSettingsPage();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('Studio V',
            style: TextStyle(
          color: Colors.white,
              fontSize: 24.0,
        )),
        centerTitle: true,
        actions: [
          Consumer<VideoEditorProvider>(
            builder: (context, provider, child) {
              if (!provider.hasProject) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.save, color: Colors.white),
                onPressed: _exportVideo,
                tooltip: 'Export',
              );
            },
          ),
        ],
      ),
      body: !_permissionsGranted
          ? _buildPermissionsRequiredView()
          : Consumer<VideoEditorProvider>(
              builder: (context, provider, child) {
                if (!provider.hasProject) {
                  return _buildWelcomeView();
                }
                return _buildEditorView(provider);
              },
            ),
    );
  }

  Widget _buildPermissionsRequiredView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.security,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Permissions Required',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please grant the necessary permissions to use the video editor.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _checkPermissions,
            child: const Text('Check Permissions'),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.video_library,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'Welcome to Video Editor',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Import media to get started',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _importMedia,
            icon: const Icon(Icons.video_file),
            label: const Text('Import Media'),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorView(VideoEditorProvider provider) {
    return Column(
      children: [
        // Video Preview Area
        Expanded(
          flex: 3,
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: Stack(
              key: _previewStackKey,
              children: [
                // Preview area: show video, image, or nothing
                Builder(
                  builder: (_) {
                    final clip = provider.currentVideoClip;
                    if (clip == null) {
                      // No clip under playhead; show black if we have a controller area, else empty
                      if (provider.previewController != null && provider.previewController!.value.isInitialized) {
                        return Center(
                          child: AspectRatio(
                            aspectRatio: provider.previewController!.value.aspectRatio,
                            child: Container(color: Colors.black),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }

                    if (clip.mediaType == MediaType.image && clip.imageFile != null) {
                      // Render image with filters/crop
                      return Center(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            children: [
                              _buildFilteredMedia(provider),
                            ],
                          ),
                        ),
                      );
                    }

                    if (provider.previewController != null && provider.previewController!.value.isInitialized) {
                      return Center(
                        child: AspectRatio(
                          aspectRatio: provider.previewController!.value.aspectRatio,
                          child: Stack(
                            children: [
                              _buildFilteredMedia(provider),
                              if (provider.isInGap)
                                Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.black,
                                ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                
                // Text Overlays
                ...provider.currentTextOverlays.map((overlay) => Positioned(
                  left: overlay.position.dx,
                  top: overlay.position.dy,
                  child: GestureDetector(
                    onTap: () => provider.selectTextOverlay(overlay.id),
                    onPanStart: (details) {
                      final renderObject = _previewStackKey.currentContext?.findRenderObject();
                      if (renderObject is RenderBox) {
                        final local = renderObject.globalToLocal(details.globalPosition);
                        _textDragOffsets[overlay.id] = local - overlay.position;
                      }
                    },
                    onPanUpdate: (details) {
                      final renderObject = _previewStackKey.currentContext?.findRenderObject();
                      if (renderObject is RenderBox) {
                        final local = renderObject.globalToLocal(details.globalPosition);
                        final delta = _textDragOffsets[overlay.id] ?? Offset.zero;
                        var newPos = local - delta;
                        // Optional: clamp within preview bounds
                        final size = renderObject.size;
                        newPos = Offset(
                          newPos.dx.clamp(0.0, size.width),
                          newPos.dy.clamp(0.0, size.height),
                        );
                        provider.updateTextOverlayPosition(overlay.id, newPos);
                      }
                    },
                    onPanEnd: (_) => _textDragOffsets.remove(overlay.id),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: provider.selectedTextOverlayId == overlay.id
                            ? Border.all(color: Colors.purple, width: 2)
                            : Border.all(color: Colors.transparent, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Transform.rotate(
                        angle: overlay.rotation,
                        child: Opacity(
                          opacity: overlay.opacity,
                          child: Text(
                            overlay.text,
                            style: TextStyle(
                              fontSize: overlay.fontSize,
                              color: overlay.color,
                              fontFamily: overlay.fontFamily,
                              fontWeight: overlay.fontWeight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )),

                // Loading Indicator
                if (provider.isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),

                // Playback Controls Overlay
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: _buildPlaybackControls(provider),
                ),
              ],
            ),
          ),
        ),

        // Bottom Toolbar (restored)
        Consumer<VideoEditorProvider>(
          builder: (context, provider, child) {
            return Container(
              color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(horizontal: 8),
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      provider.showTimeline ? Icons.timeline : Icons.timeline_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Timeline',
                    onPressed: provider.toggleTimeline,
                  ),
                  IconButton(
                    icon: Icon(
                      provider.showFilters ? Icons.tune : Icons.tune_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Filters',
                    onPressed: provider.toggleFilters,
                  ),
                  IconButton(
                    icon: Icon(
                      provider.showCropEditor ? Icons.crop : Icons.crop_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Crop',
                    onPressed: provider.toggleCropEditor,
                  ),
                  IconButton(
                    icon: Icon(
                      provider.showRotateEditor ? Icons.rotate_right : Icons.rotate_right_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Rotate',
                    onPressed: provider.toggleRotateEditor,
                  ),
                  const Spacer(),
                ],
              ),
            );
          },
        ),

        // Bottom Panel
        if (provider.showTimeline || provider.showFilters || provider.showTextEditor || provider.showAudioEditor || provider.showCropEditor || provider.showRotateEditor)
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey[900],
              child: _buildBottomPanel(provider),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaybackControls(VideoEditorProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              provider.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: provider.togglePlayback,
          ),
          Expanded(
            child: Builder(
              builder: (_) {
                final projectMs = provider.projectDuration.inMilliseconds;
                // Slider needs max > min; guard against 0 when no clips
                final maxMs = projectMs > 0 ? projectMs : 1;
                final currentMs = provider.currentPosition.inMilliseconds;
                final clampedValue = currentMs.clamp(0, maxMs).toDouble();
                return Slider(
                  value: clampedValue,
                  max: maxMs.toDouble(),
                  onChanged: (value) {
                    provider.seekTo(Duration(milliseconds: value.toInt()));
                  },
                  activeColor: Colors.purple,
                  inactiveColor: Colors.grey,
                );
              },
            ),
          ),
          Text(
            '${_formatDuration(provider.currentPosition)} / ${_formatDuration(provider.projectDuration)}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(VideoEditorProvider provider) {
    if (provider.showTimeline) {
      return const TimelineWidget();
    } else if (provider.showFilters) {
      return const FilterEditor();
    } else if (provider.showTextEditor) {
      return const TextOverlayEditor();
    } else if (provider.showAudioEditor) {
      return const AudioOverlayEditor();
    } else if (provider.showCropEditor) {
      return const CropEditor();
    } else if (provider.showRotateEditor) {
      return const RotateEditor();
    }
    return const SizedBox.shrink();
  }

  bool _isImageExtension(String? ext) {
    if (ext == null) return false;
    final e = ext.toLowerCase();
    return ['jpg','jpeg','png','gif','bmp','heic','heif','webp'].contains(e);
  }

  bool _isVideoExtension(String? ext) {
    if (ext == null) return false;
    final e = ext.toLowerCase();
    return ['mp4','mov','m4v','avi','mkv','webm'].contains(e);
  }

  Future<void> _importMedia() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4','mov','m4v','avi','mkv','webm','jpg','jpeg','png','gif','bmp','heic','heif','webp'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final provider = Provider.of<VideoEditorProvider>(context, listen: false);
        // Import each selected media in order
        for (final f in result.files) {
          final path = f.path;
          if (path == null) continue;
          final file = File(path);
          final ext = f.extension;
          if (_isImageExtension(ext)) {
            await provider.loadImageFile(file);
          } else if (_isVideoExtension(ext)) {
            await provider.loadVideoFile(file);
          }
        }
      }
    } catch (e) {
      _showErrorDialog('Failed to import media: $e');
    }
  }

  Future<void> _exportVideo() async {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    
    if (!provider.hasProject) {
      _showErrorDialog('No project to export');
      return;
    }

    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Video',
        fileName: 'edited_video.mp4',
        type: FileType.video,
      );

      if (outputPath != null) {
        _showExportDialog(provider, outputPath);
      }
    } catch (e) {
      _showErrorDialog('Failed to export video: $e');
    }
  }

  void _showExportDialog(VideoEditorProvider provider, String outputPath) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Exporting Video'),
        content: Consumer<VideoEditorProvider>(
          builder: (context, provider, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: provider.exportProgress),
                const SizedBox(height: 16),
                Text('${(provider.exportProgress * 100).toInt()}%'),
                if (provider.exportError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      provider.exportError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          if (!provider.isExporting)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
        ],
      ),
    );

    provider.exportVideo(outputPath: outputPath).then((result) {
      if (result != null) {
        Navigator.of(context).pop();
        _showSuccessDialog('Video exported successfully to: $result');
      }
    });
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

  void _showMergeDialog(VideoEditorProvider provider) {
    final clips = provider.currentProject?.videoClips ?? [];
    final selectedClipId = provider.selectedVideoClipId;
    
    if (selectedClipId == null || clips.length < 2) {
      _showErrorDialog('Please select a clip and ensure there are at least 2 clips to merge.');
      return;
    }

    final selectedIndex = clips.indexWhere((clip) => clip.id == selectedClipId);
    final adjacentClips = <VideoClip>[];
    
    // Find adjacent clips
    if (selectedIndex > 0) {
      adjacentClips.add(clips[selectedIndex - 1]);
    }
    if (selectedIndex < clips.length - 1) {
      adjacentClips.add(clips[selectedIndex + 1]);
    }

    if (adjacentClips.isEmpty) {
      _showErrorDialog('No adjacent clips found to merge with.');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge Clips'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select a clip to merge with:'),
            const SizedBox(height: 16),
            ...adjacentClips.map((clip) => ListTile(
              title: Text('Clip ${clips.indexOf(clip) + 1}'),
              subtitle: Text('${_formatDuration(clip.startTime)} - ${_formatDuration(clip.endTime)}'),
              onTap: () {
                Navigator.of(context).pop();
                provider.mergeVideoClips(selectedClipId, clip.id);
              },
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(VideoEditorProvider provider) {
    final selectedClipId = provider.selectedVideoClipId;
    
    if (selectedClipId == null) {
      _showErrorDialog('Please select a clip to delete.');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Clip'),
        content: const Text('Are you sure you want to delete this video clip? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              provider.deleteVideoClip(selectedClipId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Success'),
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

  Widget _buildFilteredMedia(VideoEditorProvider provider) {
    final colorFilter = provider.currentProject?.colorFilter ?? const ColorFilter();
    final selectedClipId = provider.selectedVideoClipId;
    double rotation = 0.0;
    
    // Get rotation from selected clip
    if (selectedClipId != null && provider.currentProject != null) {
      final clip = provider.currentProject!.videoClips
          .firstWhere((c) => c.id == selectedClipId, orElse: () => provider.currentProject!.videoClips.first);
      rotation = clip.rotation;
    }
    
    final currentClip = provider.currentVideoClip;
    Widget mediaWidget;
    if (currentClip != null && currentClip.mediaType == MediaType.image && currentClip.imageFile != null) {
      mediaWidget = SizedBox.expand(
        child: Image.file(
          currentClip.imageFile!,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          key: ValueKey(currentClip.id),
        ),
      );
    } else {
      mediaWidget = SizedBox.expand(
        child: VideoPlayer(
          provider.previewController!,
          key: ValueKey(provider.previewController),
        ),
      );
    }
    
    // Apply rotation
    if (rotation != 0.0) {
      mediaWidget = Transform.rotate(
        angle: rotation * (3.14159 / 180), // Convert degrees to radians
        child: mediaWidget,
      );
    }
    
    // Apply black and white filter
    if (colorFilter.saturation == 0.0) {
      // Simple black and white effect using blend mode
      mediaWidget = Container(
        foregroundDecoration: const BoxDecoration(
          color: Colors.grey,
          backgroundBlendMode: BlendMode.saturation,
        ),
        child: mediaWidget,
      );
    }
    
    // Apply crop from selected clip if available; otherwise use clip under playhead
    VideoClip? clipForCrop;
    if (provider.selectedVideoClipId != null && provider.currentProject != null) {
      try {
        clipForCrop = provider.currentProject!.videoClips.firstWhere(
          (c) => c.id == provider.selectedVideoClipId,
        );
      } catch (_) {
        clipForCrop = provider.currentVideoClip;
      }
    } else {
      clipForCrop = provider.currentVideoClip;
    }
    if (clipForCrop != null && clipForCrop.cropRect != null) {
      final crop = clipForCrop.cropRect!; // normalized 0..1
      final baseMediaWidget = mediaWidget; // capture to avoid recursive reference
      mediaWidget = LayoutBuilder(
        builder: (context, constraints) {
          // Original crop rect in absolute preview coordinates
          final originalRect = Rect.fromLTRB(
            crop.left * constraints.maxWidth,
            crop.top * constraints.maxHeight,
            crop.right * constraints.maxWidth,
            crop.bottom * constraints.maxHeight,
          );

          // Centered rect with same size as original crop rect
          final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
          final centeredRect = Rect.fromCenter(
            center: center,
            width: originalRect.width,
            height: originalRect.height,
          );

          // Translate video so that originalRect.center aligns under centeredRect.center
          final translate = center - originalRect.center;

          return SizedBox.expand(
            child: ClipPath(
              clipper: _RectClipper(centeredRect),
              child: Transform.translate(
                offset: translate,
                child: SizedBox.expand(child: baseMediaWidget),
              ),
            ),
          );
        },
      );
    }

    return Stack(
      children: [
        mediaWidget,
        // Apply brightness overlay
        if (colorFilter.brightness != 0.0)
          Container(
            color: colorFilter.brightness > 0 
                ? Colors.white.withOpacity(colorFilter.brightness.abs() * 0.3)
                : Colors.black.withOpacity(colorFilter.brightness.abs() * 0.3),
          ),
        // Apply contrast overlay
        if (colorFilter.contrast != 1.0)
          Container(
            color: colorFilter.contrast > 1.0
                ? Colors.white.withOpacity((colorFilter.contrast - 1.0) * 0.2)
                : Colors.black.withOpacity((1.0 - colorFilter.contrast) * 0.3),
          ),
        // Apply warmth and tint overlay
        if (colorFilter.warmth != 0.0 || colorFilter.tint != 0.0)
          Container(
            color: _getFilterOverlayColor(colorFilter),
          ),
      ],
    );
  }

  Color _getFilterOverlayColor(ColorFilter filter) {
    // Calculate overlay color based on filter settings
    double r = 0.5;
    double g = 0.5;
    double b = 0.5;
    
    // Apply warmth
    if (filter.warmth != 0.0) {
      r += filter.warmth * 0.2;
      b -= filter.warmth * 0.2;
    }
    
    // Apply tint
    if (filter.tint != 0.0) {
      g += filter.tint * 0.1;
    }
    
    // Clamp values
    r = r.clamp(0.0, 1.0);
    g = g.clamp(0.0, 1.0);
    b = b.clamp(0.0, 1.0);
    
    // Calculate opacity based on filter intensity
    double opacity = 0.0;
    if (filter.contrast != 1.0) opacity += (filter.contrast - 1.0).abs() * 0.2;
    if (filter.saturation != 1.0) opacity += (filter.saturation - 1.0).abs() * 0.3;
    if (filter.warmth != 0.0) opacity += filter.warmth.abs() * 0.2;
    if (filter.tint != 0.0) opacity += filter.tint.abs() * 0.2;
    
    opacity = opacity.clamp(0.0, 0.5);
    
    return Color.fromRGBO(
      (r * 255).toInt(),
      (g * 255).toInt(),
      (b * 255).toInt(),
      opacity,
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
