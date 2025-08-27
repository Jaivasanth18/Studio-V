import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';

class TimelineWidget extends StatefulWidget {
  const TimelineWidget({super.key});

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  final ScrollController _scrollController = ScrollController();
  double _timelineScale = 0.01;
  static const double _trackHeight = 60.0;
  static const double _timelineHeight = 40.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showMixerDialog(BuildContext context, VideoEditorProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        double videoVol = provider.videoMasterVolume;
        double audioVol = provider.audioMasterVolume;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Audio Mixer'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Video Master', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${(videoVol * 100).round()}%'),
                      ],
                    ),
                    Slider(
                      value: videoVol.clamp(0.0, 1.0),
                      onChanged: (v) {
                        setState(() => videoVol = v);
                        provider.setVideoMasterVolume(v);
                      },
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Audio Master', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('${(audioVol * 100).round()}%'),
                      ],
                    ),
                    Slider(
                      value: audioVol.clamp(0.0, 1.0),
                      onChanged: (v) {
                        setState(() => audioVol = v);
                        provider.setAudioMasterVolume(v);
                      },
                      min: 0.0,
                      max: 1.0,
                      divisions: 100,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        if (!provider.hasProject) {
          return const Center(
            child: Text(
              'No project loaded',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return Column(
          children: [
            _buildTimelineHeader(provider),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  child: Container(
                    width: _getTimelineWidth(provider.totalDuration),
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            _buildTimeRuler(provider),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildTextOverlayTrack(provider),
                                    _buildVideoTracks(provider),
                                    _buildAudioOverlayTrack(provider),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Global playhead that spans all tracks
                        Positioned(
                          left: (_durationToPixels(provider.currentPosition) - 1).clamp(0.0, double.infinity),
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              width: 2,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        // Top-layer raw pointer listener to seek wherever user taps/clicks
                        Positioned.fill(
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (event) {
                              final provider = Provider.of<VideoEditorProvider>(context, listen: false);
                              // localPosition is in the scrolled content's coordinates; no need to add scroll offset
                              final tapX = event.localPosition.dx;
                              final totalTimelineWidth = _getTimelineWidth(provider.totalDuration);
                              final ratio = (tapX / totalTimelineWidth).clamp(0.0, 1.0);
                              final target = Duration(
                                milliseconds: (provider.totalDuration.inMilliseconds * ratio).round(),
                              );
                              provider.seekTo(target);
                              _scrollToPosition(target);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildTimelineControls(provider),
          ],
        );
      },
    );
  }

  Widget _buildTimelineHeader(VideoEditorProvider provider) {
    return Container(
      height: 50,
      color: Colors.grey[800],
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Timeline',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.equalizer, color: Colors.white),
            onPressed: () => _showMixerDialog(context, provider),
            tooltip: 'Mixer',
          ),
          IconButton(
            icon: const Icon(Icons.text_fields, color: Colors.white),
            onPressed: () => provider.toggleTextEditor(),
            tooltip: 'Add Text',
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            onPressed: () => provider.toggleAudioEditor(),
            tooltip: 'Add Audio',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white),
            onPressed: () => _zoomTimeline(true),
            tooltip: 'Zoom In',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white),
            onPressed: () => _zoomTimeline(false),
            tooltip: 'Zoom Out',
          ),
        ],
      ),
    );
  }

  // Canva-like circular gradient plus button
  Widget _buildCanvaPlusButton({required VoidCallback onTap, String? tooltip}) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF6819F1), // purple-600
                Color(0xFFDCB6F1), // cyan-500
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: const Center(
            child: Icon(Icons.add, color: Colors.white, size: 24,fill: 0.7),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildTimeRuler(VideoEditorProvider provider) {
    return Container(
      height: _timelineHeight,
      color: Colors.grey[850],
      child: Stack(
        children: [
          CustomPaint(
            painter: TimeRulerPainter(
              duration: provider.totalDuration,
              scale: _timelineScale,
              currentPosition: provider.currentPosition,
            ),
            size: Size(_getTimelineWidth(provider.totalDuration), _timelineHeight),
          ),
          // Playhead indicator (circle only, line handled globally)
          Positioned(
            left: (_durationToPixels(provider.currentPosition) - 6).clamp(0.0, double.infinity),
            top: 0,
            child: IgnorePointer(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoTracks(VideoEditorProvider provider) {
    return DragTarget<VideoClip>(
      onWillAccept: (data) => data != null,
      onAcceptWithDetails: (details) {
        // Get the scroll offset to account for horizontal scrolling
        final scrollOffset = _scrollController.offset;
        
        // Calculate new position based on drop location - allow full 60-minute range
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.offset);
        
        // Add scroll offset to get the actual timeline position
        final timelineX = localPosition.dx + scrollOffset;
        final dropTime = Duration(
          milliseconds: (timelineX / _timelineScale).round(),
        );
        // Use new reorder API: repack clips sequentially like InShot
        provider.reorderVideoClip(details.data.id, dropTime);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: _trackHeight,
          color: candidateData.isNotEmpty ? Colors.grey[800] : Colors.grey[900],
          child: Stack(
            children: [
              // Full-area tap-to-seek handler for the video track
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) => _handleTapSeek(details.localPosition.dx, provider),
                ),
              ),
              // Track background
              Container(
                width: double.infinity,
                height: _trackHeight,
                decoration: BoxDecoration(
                  color: candidateData.isNotEmpty ? Colors.grey[800] : Colors.grey[900],
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[700]!, width: 1),
                  ),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Text(
                      'Video',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              // Video clips
              ...provider.currentProject!.videoClips.map((clip) => 
                _buildVideoClipWidget(clip, provider)
              ),
              // Black sections for gaps
              ..._buildBlackSections(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextOverlayTrack(VideoEditorProvider provider) {
    return DragTarget<TextOverlay>(
      onWillAccept: (data) => data != null,
      onAcceptWithDetails: (details) {
        // Get the scroll offset to account for horizontal scrolling
        final scrollOffset = _scrollController.offset;
        
        // Calculate new position based on drop location
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.offset);
        
        // Add scroll offset to get the actual timeline position
        final timelineX = localPosition.dx + scrollOffset;
        final newStartTime = Duration(
          milliseconds: (timelineX / _timelineScale).round(),
        );
        
        // Clamp to 300 seconds max duration
        final duration = details.data.endTime - details.data.startTime;
        final clampedStartTime = Duration(
          milliseconds: newStartTime.inMilliseconds.clamp(0, const Duration(seconds: 300).inMilliseconds - duration.inMilliseconds),
        );
        
        provider.moveTextOverlay(details.data.id, clampedStartTime);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: _trackHeight,
          color: candidateData.isNotEmpty ? Colors.grey[800] : Colors.grey[900],
          child: Stack(
            children: [
              // Full-area tap-to-seek handler for the text track
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) => _handleTapSeek(details.localPosition.dx, provider),
                ),
              ),
              // Track background
              Container(
                width: double.infinity,
                height: _trackHeight,
                decoration: BoxDecoration(
                  color: candidateData.isNotEmpty ? Colors.grey[800] : Colors.grey[900],
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[700]!),
                  ),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Text(
                      'Text',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              // Text overlays
              ...provider.currentProject!.textOverlays.map((overlay) => 
                _buildTextOverlayWidget(overlay, provider)
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAudioOverlayTrack(VideoEditorProvider provider) {
    return DragTarget<AudioOverlay>(
      onWillAccept: (data) => data != null,
      onAcceptWithDetails: (details) {
        // Account for horizontal scroll
        final scrollOffset = _scrollController.offset;
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        final localPosition = renderBox.globalToLocal(details.offset);

        final timelineX = localPosition.dx + scrollOffset;
        final newStartTime = Duration(
          milliseconds: (timelineX / _timelineScale).round(),
        );

        provider.moveAudioOverlay(details.data.id, newStartTime);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          height: _trackHeight,
          color: candidateData.isNotEmpty ? Colors.grey[800] : Colors.grey[900],
          child: Stack(
            children: [
              // Full-area tap-to-seek handler for the audio track
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (details) => _handleTapSeek(details.localPosition.dx, provider),
                ),
              ),
              // Track background
              Container(
                width: double.infinity,
                height: _trackHeight,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[700]!),
                  ),
                ),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Text(
                      'Audio',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              // Audio overlays
              ...provider.currentProject!.audioOverlays.map((overlay) =>
                _buildAudioOverlayWidget(overlay, provider)
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoClipWidget(VideoClip clip, VideoEditorProvider provider) {
    final left = _durationToPixels(clip.startTime);
    final width = _durationToPixels(clip.duration);
    final isSelected = provider.selectedVideoClipId == clip.id;

    return Positioned(
      left: left,
      top: 20,
      child: LongPressDraggable<VideoClip>(
        data: clip,
        axis: Axis.horizontal,
        dragAnchorStrategy: (draggable, context, position) {
          // Use pointer position as anchor for more natural dragging
          return Offset(width / 2, (_trackHeight - 20) / 2);
        },
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: width,
            height: _trackHeight - 20,
            decoration: BoxDecoration(
              color: Colors.blue[400]!.withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: const Center(
              child: Icon(Icons.video_library, color: Colors.white, size: 16),
            ),
          ),
        ),
        childWhenDragging: Container(
          width: width,
          height: _trackHeight - 20,
          decoration: BoxDecoration(
            color: Colors.grey[600]!.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey, width: 1),
          ),
        ),
        child: GestureDetector(
          onTap: () => provider.selectVideoClip(clip.id),
          child: Container(
            width: width,
            height: _trackHeight - 20,
            decoration: BoxDecoration(
              color: isSelected ? Colors.purple[400] : Colors.purple[400],
              borderRadius: BorderRadius.circular(4),
              border: isSelected ? Border.all(color: Colors.purple, width: 2) : null,
            ),
            child: Stack(
              children: [
                // Clip info
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Video Clip',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDuration(clip.duration),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Start: ${_formatDuration(clip.startTime)}',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Resize handles
                if (isSelected) ...[
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      color: Colors.purple,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      color: Colors.purple,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextOverlayWidget(TextOverlay overlay, VideoEditorProvider provider) {
    final left = _durationToPixels(overlay.startTime);
    final width = _durationToPixels(overlay.endTime - overlay.startTime);
    final isSelected = provider.selectedTextOverlayId == overlay.id;

    return Positioned(
      left: left,
      top: 20,
      child: Draggable<TextOverlay>(
        data: overlay,
        axis: Axis.horizontal,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: width,
            height: _trackHeight - 20,
            decoration: BoxDecoration(
              color: Colors.green[600]!.withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                overlay.text,
                style: const TextStyle(color: Colors.white, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        child: GestureDetector(
          onTap: () => provider.selectTextOverlay(overlay.id),
          child: Container(
            width: width,
            height: _trackHeight - 20,
            decoration: BoxDecoration(
              color: isSelected ? Colors.green[600] : Colors.green[800],
              borderRadius: BorderRadius.circular(4),
              border: isSelected ? Border.all(color: Colors.green, width: 2) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overlay.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatDuration(overlay.endTime - overlay.startTime),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioOverlayWidget(AudioOverlay overlay, VideoEditorProvider provider) {
    final left = _durationToPixels(overlay.startTime);
    final width = _durationToPixels(overlay.endTime - overlay.startTime);
    final isSelected = provider.selectedAudioOverlayId == overlay.id;

    return Positioned(
      left: left,
      top: 20,
      child: Draggable<AudioOverlay>(
        data: overlay,
        axis: Axis.horizontal,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: width,
            height: _trackHeight - 20,
            decoration: BoxDecoration(
              color: Colors.orange[600]!.withOpacity(0.8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Icon(Icons.audiotrack, color: Colors.white, size: 16),
            ),
          ),
        ),
        child: GestureDetector(
          onTap: () => provider.selectAudioOverlay(overlay.id),
          onDoubleTap: () {
            provider.selectAudioOverlay(overlay.id);
            provider.toggleAudioEditor();
          },
          child: Container(
            width: width,
            height: _trackHeight - 20,
            decoration: BoxDecoration(
              color: isSelected ? Colors.orange[600] : Colors.orange[800],
              borderRadius: BorderRadius.circular(4),
              border: isSelected ? Border.all(color: Colors.orange, width: 2) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.audiotrack, color: Colors.white, size: 12),
                      SizedBox(width: 2),
                      Text(
                        'Audio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatDuration(overlay.endTime - overlay.startTime),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineControls(VideoEditorProvider provider) {
    return Container(
      height: 60,
      color: Colors.grey[800],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Cut Button (works for selected video clip or audio overlay)
          IconButton(
            onPressed: provider.selectedVideoClipId != null || provider.selectedAudioOverlayId != null
                ? () {
                    if (provider.selectedVideoClipId != null) {
                      provider.cutVideoClip(provider.selectedVideoClipId!);
                    } else if (provider.selectedAudioOverlayId != null) {
                      provider.cutAudioOverlay(provider.selectedAudioOverlayId!);
                    }
                  }
                : null,
            icon: const Icon(Icons.content_cut, size: 24),
            tooltip: 'Cut',
          ),

          // Canva-style Add (+) Button to import media into timeline
          _buildCanvaPlusButton(
            onTap: _importMediaFromTimeline,
            tooltip: 'Add Media',
          ),

          // Delete Button (works for selected video clip or audio overlay)
          IconButton(
            onPressed: provider.selectedVideoClipId != null || provider.selectedAudioOverlayId != null
                ? () => _showDeleteDialog(context, provider)
                : null,
            icon: const Icon(Icons.delete, size: 24),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  double _getTimelineWidth(Duration duration) {
    // Always use the full 60-minute timeline width regardless of video content
    const fullTimelineDuration = Duration(hours: 1);
    return (fullTimelineDuration.inMilliseconds * _timelineScale).clamp(400.0, 50000.0);
  }

  double _durationToPixels(Duration duration) {
    return duration.inMilliseconds * _timelineScale;
  }
  
  /// Get playhead position accounting for scroll
  double _getPlayheadPosition(Duration position) {
    return _durationToPixels(position);
  }

  // Map a local tap x (within a track stack) to a timeline position and seek
  void _handleTapSeek(double localDx, VideoEditorProvider provider) {
    final scrollOffset = _scrollController.offset;
    final tapX = localDx + scrollOffset;
    final totalTimelineWidth = _getTimelineWidth(provider.totalDuration);
    final timelineRatio = (tapX / totalTimelineWidth).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (provider.totalDuration.inMilliseconds * timelineRatio).round(),
    );
    provider.seekTo(target);
    _scrollToPosition(target);
  }

  // Smoothly scroll the timeline so that the given position is centered when possible
  void _scrollToPosition(Duration position) {
    // Skip if scroll metrics not attached yet
    if (!_scrollController.hasClients) return;
    final contentWidth = _getTimelineWidth(const Duration(hours: 1));
    final viewport = _scrollController.position.viewportDimension;
    final targetX = _durationToPixels(position);
    double desiredOffset = targetX - viewport / 2;
    desiredOffset = desiredOffset.clamp(0.0, (contentWidth - viewport).clamp(0.0, double.infinity));
    _scrollController.animateTo(
      desiredOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _zoomTimeline(bool zoomIn) {
    setState(() {
      if (zoomIn) {
        _timelineScale = (_timelineScale * 1.5).clamp(0.001, 2.0);
      } else {
        _timelineScale = (_timelineScale / 1.5).clamp(0.001, 2.0);
      }
    });
  }

  Future<void> _importMediaFromTimeline() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4','mov','m4v','avi','mkv','webm','jpg','jpeg','png','gif','bmp','heic','heif','webp'],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final provider = Provider.of<VideoEditorProvider>(context, listen: false);
        for (final f in result.files) {
          final path = f.path;
          if (path == null) continue;
          final file = File(path);
          final ext = f.extension?.toLowerCase();
          if (ext == null) continue;
          if (['jpg','jpeg','png','gif','bmp','heic','heif','webp'].contains(ext)) {
            await provider.loadImageFile(file);
          } else if (['mp4','mov','m4v','avi','mkv','webm'].contains(ext)) {
            await provider.loadVideoFile(file);
          }
        }
      }
    } catch (_) {
      // Swallow errors here; main screen handles user-facing dialogs
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Build black sections to represent gaps between clips
  List<Widget> _buildBlackSections(VideoEditorProvider provider) {
    if (provider.currentProject == null || provider.currentProject!.videoClips.isEmpty) {
      return [];
    }

    final clips = List<VideoClip>.from(provider.currentProject!.videoClips)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    
    final blackSections = <Widget>[];
    
    // Add black section from start to first clip
    if (clips.first.startTime > Duration.zero) {
      final width = _durationToPixels(clips.first.startTime);
      blackSections.add(
        Positioned(
          left: 0,
          top: 20,
          child: Container(
            width: width,
            height: _trackHeight - 20,
            decoration: BoxDecoration(
              color: Colors.grey[800]!.withOpacity(0.7),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.grey[600]!, width: 1),
            ),
            child: const Center(
              child: Icon(
                Icons.block,
                color: Colors.white38,
                size: 12,
              ),
            ),
          ),
        ),
      );
    }
    
    // Add black sections between clips
    for (int i = 0; i < clips.length - 1; i++) {
      final currentClip = clips[i];
      final nextClip = clips[i + 1];
      
      if (currentClip.endTime < nextClip.startTime) {
        final left = _durationToPixels(currentClip.endTime);
        final width = _durationToPixels(nextClip.startTime - currentClip.endTime);
        
        blackSections.add(
          Positioned(
            left: left,
            top: 20,
            child: Container(
              width: width,
              height: _trackHeight - 20,
              decoration: BoxDecoration(
                color: Colors.grey[800]!.withOpacity(0.7),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: Colors.grey[600]!, width: 1),
              ),
              child: const Center(
                child: Icon(
                  Icons.block,
                  color: Colors.white38,
                  size: 12,
                ),
              ),
            ),
          ),
        );
      }
    }
    
    return blackSections;
  }


  void _showDeleteDialog(BuildContext context, VideoEditorProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete the selected item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (provider.selectedVideoClipId != null) {
                provider.deleteVideoClip(provider.selectedVideoClipId!);
              } else if (provider.selectedAudioOverlayId != null) {
                provider.removeAudioOverlay(provider.selectedAudioOverlayId!);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class TimeRulerPainter extends CustomPainter {
  final Duration duration;
  final double scale;
  final Duration currentPosition;

  TimeRulerPainter({
    required this.duration,
    required this.scale,
    required this.currentPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Calculate appropriate interval based on scale to prevent overlap
    final totalSeconds = duration.inSeconds;
    final pixelsPerSecond = totalSeconds > 0 ? size.width / totalSeconds : 0;
    
    // Determine label interval based on available space
    int labelInterval;
    if (pixelsPerSecond > 50) {
      labelInterval = 5; // Every 5 seconds when zoomed in
    } else if (pixelsPerSecond > 20) {
      labelInterval = 10; // Every 10 seconds
    } else if (pixelsPerSecond > 5) {
      labelInterval = 30; // Every 30 seconds
    } else if (pixelsPerSecond > 1) {
      labelInterval = 60; // Every minute
    } else if (pixelsPerSecond > 0.2) {
      labelInterval = 300; // Every 5 minutes
    } else {
      labelInterval = 600; // Every 10 minutes when zoomed out
    }

    // Draw time markers
    for (int i = 0; i <= totalSeconds; i += labelInterval) {
      final x = (i * pixelsPerSecond).toDouble();
      
      // Draw tick mark
      canvas.drawLine(
        Offset(x, size.height - 10),
        Offset(x, size.height),
        paint,
      );

      // Draw time label
      final minutes = i ~/ 60;
      final seconds = i % 60;
      final timeText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      
      textPainter.text = TextSpan(
        text: timeText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
        ),
      );
      textPainter.layout();
      
      // Ensure label doesn't go outside bounds
      final labelX = (x - textPainter.width / 2).clamp(0.0, size.width - textPainter.width);
      textPainter.paint(
        canvas,
        Offset(labelX, size.height - 30),
      );
    }

    // Current position indicator removed - handled by global playhead
  }

  @override
  bool shouldRepaint(TimeRulerPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition ||
           oldDelegate.duration != duration ||
           oldDelegate.scale != scale;
  }
}
