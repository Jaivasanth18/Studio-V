import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_editor/video_editor.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'package:just_audio/just_audio.dart';
import '../models/video_project.dart';

/// Provider for managing video editing state and operations
class VideoEditorProvider extends ChangeNotifier {
  VideoProject? _currentProject;
  VideoEditorController? _videoController;
  // Active preview controller and a pool of controllers per source file
  VideoPlayerController? _previewController;
  final Map<String, VideoPlayerController> _previewControllers = {};
  String? _activeFilePath;
  
  // Playback state
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  bool _isLoading = false;
  
  // Timeline clock for continuous playback through gaps
  Timer? _timelineTimer;
  DateTime? _playbackStartTime;
  Duration? _playbackStartPosition;
  
  // Editing state
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String? _exportError;
  
  // UI state
  bool _showTimeline = true;
  bool _showFilters = false;
  bool _showTextEditor = false;
  bool _showAudioEditor = false;
  bool _showCropEditor = false;
  bool _showRotateEditor = false;
  
  // Selected items
  String? _selectedTextOverlayId;
  String? _selectedAudioOverlayId;
  String? _selectedVideoClipId;

  // Master volumes
  double _videoMasterVolume = 1.0; // scales clip volumes
  double _audioMasterVolume = 1.0; // scales audio overlay volumes
  
  final Uuid _uuid = const Uuid();
  // Audio players per overlay
  final Map<String, AudioPlayer> _audioPlayers = {};

  // Getters
  VideoProject? get currentProject => _currentProject;
  VideoEditorController? get videoController => _videoController;
  VideoPlayerController? get previewController => _previewController;
  String? get activeFilePath => _activeFilePath;
  
  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;
  bool get isLoading => _isLoading;
  
  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  String? get exportError => _exportError;
  
  bool get showTimeline => _showTimeline;
  bool get showFilters => _showFilters;
  bool get showTextEditor => _showTextEditor;
  bool get showAudioEditor => _showAudioEditor;
  bool get showCropEditor => _showCropEditor;
  bool get showRotateEditor => _showRotateEditor;
  
  String? get selectedTextOverlayId => _selectedTextOverlayId;
  String? get selectedAudioOverlayId => _selectedAudioOverlayId;
  String? get selectedVideoClipId => _selectedVideoClipId;
  double get videoMasterVolume => _videoMasterVolume;
  double get audioMasterVolume => _audioMasterVolume;

  /// Set master volume for video track (0..1) and apply immediately to preview
  Future<void> setVideoMasterVolume(double v) async {
    final newVal = v.clamp(0.0, 1.0);
    if (_videoMasterVolume == newVal) return;
    _videoMasterVolume = newVal;
    await _applyPreviewVolumeForCurrentPosition();
    notifyListeners();
  }

  /// Set master volume for audio overlays (0..1) and apply immediately to active players
  Future<void> setAudioMasterVolume(double v) async {
    final newVal = v.clamp(0.0, 1.0);
    if (_audioMasterVolume == newVal) return;
    _audioMasterVolume = newVal;
    // Apply to all existing players based on their overlay volume
    if (_currentProject != null) {
      for (final overlay in _currentProject!.audioOverlays) {
        final p = _audioPlayers[overlay.id];
        if (p != null) {
          await p.setVolume((overlay.volume * _audioMasterVolume).clamp(0.0, 1.0));
        }
      }
    }
    notifyListeners();
  }
  
  /// Get the dynamic project duration based on the last clip's end time
  Duration get totalDuration {
    if (_currentProject == null) {
      return const Duration(hours: 1);
    }

    // Duration from video clips
    final clipsDuration = _currentProject!.videoClips.isEmpty
        ? Duration.zero
        : _currentProject!.calculateTotalDuration();

    // Duration from audio overlays (allow timeline to extend to fit audio)
    Duration overlaysDuration = Duration.zero;
    for (final a in _currentProject!.audioOverlays) {
      if (a.endTime > overlaysDuration) overlaysDuration = a.endTime;
    }

    final calculated = clipsDuration > overlaysDuration ? clipsDuration : overlaysDuration;
    // Ensure minimum 60-minute timeline for editing
    return calculated > const Duration(hours: 1)
        ? calculated
        : const Duration(hours: 1);
  }

  /// Switch the active preview controller based on target file path
  void _switchActivePreviewController(String filePath) {
    if (_activeFilePath == filePath && _previewController != null) return;
    // Detach listener and pause/mute old controller to avoid lingering texture/audio
    final old = _previewController;
    old?.removeListener(_videoPositionListener);
    if (old != null && old.value.isInitialized) {
      old.pause();
      old.setVolume(0.0);
    }
    _previewController = _previewControllers[filePath];
    _activeFilePath = filePath;
    _previewController?.addListener(_videoPositionListener);
    // Force UI rebuild so VideoPlayer binds to the new controller immediately
    notifyListeners();
  }

  /// Move audio overlay to a new start time by drag on timeline
  Future<void> moveAudioOverlay(String overlayId, Duration newStartTime) async {
    if (_currentProject == null) return;

    final index = _currentProject!.audioOverlays.indexWhere((o) => o.id == overlayId);
    if (index == -1) return;

    final overlay = _currentProject!.audioOverlays[index];
    final duration = overlay.endTime - overlay.startTime;

    // Clamp within the dynamic total timeline length
    final maxTimeline = totalDuration;
    Duration desiredStart = newStartTime;
    if (desiredStart < Duration.zero) desiredStart = Duration.zero;
    final maxStart = maxTimeline - duration;
    if (desiredStart > maxStart) desiredStart = maxStart;

    final updated = overlay.copyWith(
      startTime: desiredStart,
      endTime: desiredStart + duration,
    );

    _currentProject = _currentProject!.updateAudioOverlay(overlayId, updated);
    notifyListeners();
  }
  
  /// Get the actual project end time (for display purposes)
  Duration get projectDuration => _currentProject?.calculateTotalDuration() ?? Duration.zero;
  
  /// Get the actual video duration for display purposes
  Duration get videoDuration => _previewController?.value.duration ?? Duration.zero;

  /// Cut video clip at current position
  void cutVideoClip(String clipId) {
    if (_currentProject == null) return;
    
    final clipIndex = _currentProject!.videoClips.indexWhere((clip) => clip.id == clipId);
    if (clipIndex == -1) return;
    
    final originalClip = _currentProject!.videoClips[clipIndex];
    final cutPosition = _currentPosition;
    
    // Don't cut if position is at the start or end
    if (cutPosition <= originalClip.startTime || cutPosition >= originalClip.endTime) return;
    
    // Map timeline cut to source position
    final firstDuration = cutPosition - originalClip.startTime;
    final firstSourceEnd = originalClip.sourceStart + firstDuration;

    // Create two new clips preserving source mapping
    final firstClip = VideoClip(
      id: _uuid.v4(),
      mediaType: originalClip.mediaType,
      videoFile: originalClip.videoFile,
      imageFile: originalClip.imageFile,
      startTime: originalClip.startTime,
      endTime: cutPosition,
      sourceStart: originalClip.sourceStart,
      sourceEnd: firstSourceEnd,
    );
    
    final secondClip = VideoClip(
      id: _uuid.v4(),
      mediaType: originalClip.mediaType,
      videoFile: originalClip.videoFile,
      imageFile: originalClip.imageFile,
      startTime: cutPosition,
      endTime: originalClip.endTime,
      sourceStart: firstSourceEnd,
      sourceEnd: originalClip.sourceEnd,
    );
    
    // Update project with new clips
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips.removeAt(clipIndex);
    updatedClips.insert(clipIndex, firstClip);
    updatedClips.insert(clipIndex + 1, secondClip);
    
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    notifyListeners();
  }

  /// Reorder clip by long-press drag like InShot: insert into sequence and repack with no gaps
  void reorderVideoClip(String clipId, Duration dropTime) {
    if (_currentProject == null) return;

    final clips = List<VideoClip>.from(_currentProject!.videoClips);
    final currentIndex = clips.indexWhere((c) => c.id == clipId);
    if (currentIndex == -1) return;

    // Remove the dragged clip
    final moving = clips.removeAt(currentIndex);

    // Determine target insert index based on dropTime relative to remaining clips
    // Use midpoints between each clip's start/end to decide before/after
    int insertIndex = clips.length; // default at end
    for (int i = 0; i < clips.length; i++) {
      final c = clips[i];
      final mid = c.startTime + (c.endTime - c.startTime) ~/ 2;
      if (dropTime < mid) {
        insertIndex = i;
        break;
      }
    }

    // Insert moving clip
    clips.insert(insertIndex, moving);

    // Repack: set start/end sequentially with no gaps, starting at 0
    Duration cursor = Duration.zero;
    final repacked = <VideoClip>[];
    for (final c in clips) {
      final dur = c.endTime - c.startTime;
      final updated = c.copyWith(startTime: cursor, endTime: cursor + dur);
      repacked.add(updated);
      cursor += dur;
    }

    _currentProject = _currentProject!.copyWith(videoClips: repacked);
    notifyListeners();
  }

  /// Merge two adjacent video clips
  void mergeVideoClips(String firstClipId, String secondClipId) {
    if (_currentProject == null) return;
    
    final firstIndex = _currentProject!.videoClips.indexWhere((clip) => clip.id == firstClipId);
    final secondIndex = _currentProject!.videoClips.indexWhere((clip) => clip.id == secondClipId);
    
    if (firstIndex == -1 || secondIndex == -1) return;
    if ((firstIndex - secondIndex).abs() != 1) return; // Must be adjacent
    
    final firstClip = _currentProject!.videoClips[firstIndex];
    final secondClip = _currentProject!.videoClips[secondIndex];
    
    // Only merge video clips from the same source, continuous
    if (firstClip.mediaType != MediaType.video || secondClip.mediaType != MediaType.video) return;
    if (firstClip.videoFile == null || secondClip.videoFile == null) return;
    if (firstClip.videoFile!.path != secondClip.videoFile!.path) return;
    if (firstClip.endTime != secondClip.startTime) return;
    
    // Create merged clip
    final mergedClip = VideoClip(
      id: _uuid.v4(),
      mediaType: MediaType.video,
      videoFile: firstClip.videoFile,
      startTime: firstClip.startTime,
      endTime: secondClip.endTime,
    );
    
    // Update project
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    final minIndex = firstIndex < secondIndex ? firstIndex : secondIndex;
    final maxIndex = firstIndex > secondIndex ? firstIndex : secondIndex;
    
    updatedClips.removeAt(maxIndex);
    updatedClips.removeAt(minIndex);
    updatedClips.insert(minIndex, mergedClip);
    
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    notifyListeners();
  }

  /// Delete a video clip
  void deleteVideoClip(String clipId) {
    if (_currentProject == null) return;
    
    final updatedClips = _currentProject!.videoClips.where((clip) => clip.id != clipId).toList();
    
    // If this was the selected clip, clear selection
    if (_selectedVideoClipId == clipId) {
      _selectedVideoClipId = null;
    }
    
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    notifyListeners();
  }

  /// Move video clip to new position
  void moveVideoClip(String clipId, Duration newStartTime) {
    if (_currentProject == null) return;
    
    final clipIndex = _currentProject!.videoClips.indexWhere((clip) => clip.id == clipId);
    if (clipIndex == -1) return;
    
    final originalClip = _currentProject!.videoClips[clipIndex];
    final clipDuration = originalClip.endTime - originalClip.startTime;
    
    // Allow positioning anywhere within the full timeline (60 minutes)
    const maxTimelineDuration = Duration(hours: 1);
    final maxStartTime = maxTimelineDuration - clipDuration;
    Duration desiredStart = newStartTime;
    if (desiredStart < Duration.zero) desiredStart = Duration.zero;
    if (desiredStart > maxStartTime) desiredStart = maxStartTime;

    // Build a list of other clips (excluding the one being moved), sorted by start time
    final otherClips = List<VideoClip>.from(_currentProject!.videoClips)
      ..removeAt(clipIndex);
    otherClips.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Compute available gaps [gapStart, gapEnd) that can host the moved clip
    final gaps = <List<Duration>>[];
    Duration cursor = Duration.zero;
    for (final c in otherClips) {
      if (c.startTime > cursor) {
        gaps.add([cursor, c.startTime]);
      }
      if (c.endTime > cursor) cursor = c.endTime;
    }
    // Tail gap until max timeline duration
    if (cursor < maxTimelineDuration) {
      gaps.add([cursor, maxTimelineDuration]);
    }

    // Choose the best gap: one that fits clipDuration and whose start is closest to desiredStart
    Duration? chosenStart;
    Duration bestDistance = maxTimelineDuration; // large initial value
    for (final g in gaps) {
      final gapStart = g[0];
      final gapEnd = g[1];
      final available = gapEnd - gapStart;
      if (available < clipDuration) continue; // cannot fit

      // Clamp desiredStart within this gap so that the whole clip fits
      final minStart = gapStart;
      final maxStartInGap = gapEnd - clipDuration;
      final clamped = desiredStart < minStart
          ? minStart
          : (desiredStart > maxStartInGap ? maxStartInGap : desiredStart);

      // Distance from desired to actual placement
      final distance = (clamped - desiredStart).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        chosenStart = clamped;
        // Early exit on perfect match
        if (bestDistance == Duration.zero) break;
      }
    }

    // If no gap can fit (should be rare if timeline < 60m), place at end of last clip within bounds
    chosenStart ??= (otherClips.isEmpty ? Duration.zero : otherClips.last.endTime);
    if (chosenStart > maxStartTime) chosenStart = maxStartTime;

    // Update only timeline position, preserve source in/out
    final updatedClip = originalClip.copyWith(
      startTime: chosenStart,
      endTime: chosenStart + clipDuration,
    );

    // Update project with moved clip
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;

    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    notifyListeners();
  }
  bool get hasProject => _currentProject != null;
  bool get hasVideoController => _videoController != null;

  /// Create a new video project
  Future<void> createNewProject(String name) async {
    _currentProject = VideoProject(
      id: _uuid.v4(),
      name: name,
    );
    
    _resetControllers();
    notifyListeners();
  }

  /// Load a video file and create/update the project
  Future<void> loadVideoFile(File videoFile) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // If first import, set up a VideoEditorController (optional for basic playback)
      _videoController ??= VideoEditorController.file(
        videoFile,
        minDuration: const Duration(seconds: 1),
        maxDuration: const Duration(minutes: 10),
      );
      if (!_videoController!.initialized) {
        await _videoController!.initialize();
      }

      // Create or reuse a preview controller for this file, do NOT dispose existing ones
      final path = videoFile.path;
      var controller = _previewControllers[path];
      if (controller == null) {
        controller = VideoPlayerController.file(
          videoFile,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        await controller.initialize();
        await controller.setVolume(0.0); // Always mute; overlays provide sound
        _previewControllers[path] = controller;
      }

      // Create or update project with video clip
      final videoDuration = controller.value.duration;

      // Determine next available start time to avoid overlap
      Duration nextStart = Duration.zero;
      if (_currentProject != null && _currentProject!.videoClips.isNotEmpty) {
        // Find max endTime among existing clips
        for (final c in _currentProject!.videoClips) {
          if (c.endTime > nextStart) nextStart = c.endTime;
        }
      }

      final videoClip = VideoClip(
        id: _uuid.v4(),
        mediaType: MediaType.video,
        videoFile: videoFile,
        startTime: nextStart,
        endTime: nextStart + videoDuration,
        // Keep source mapping relative to the media itself
        sourceStart: Duration.zero,
        sourceEnd: videoDuration,
      );

      if (_currentProject == null) {
        _currentProject = VideoProject(
          id: _uuid.v4(),
          name: 'New Project',
          videoClips: [videoClip],
          totalDuration: const Duration(hours: 1),
        );
      } else {
        _currentProject = _currentProject!.addVideoClip(videoClip);
      }

      // If there is no active preview yet, activate this file's controller
      if (_previewController == null) {
        _switchActivePreviewController(path);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _exportError = 'Failed to load video: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Load an image file as a timeline clip with a fixed default duration (3s)
  Future<void> loadImageFile(File imageFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Determine next available start time (end of last existing clip)
      Duration nextStart = Duration.zero;
      if (_currentProject != null && _currentProject!.videoClips.isNotEmpty) {
        for (final c in _currentProject!.videoClips) {
          if (c.endTime > nextStart) nextStart = c.endTime;
        }
      }

      const imageDuration = Duration(seconds: 3);
      final imageClip = VideoClip(
        id: _uuid.v4(),
        mediaType: MediaType.image,
        imageFile: imageFile,
        startTime: nextStart,
        endTime: nextStart + imageDuration,
        sourceStart: Duration.zero,
        sourceEnd: imageDuration,
      );

      if (_currentProject == null) {
        _currentProject = VideoProject(
          id: _uuid.v4(),
          name: 'New Project',
          videoClips: [imageClip],
          totalDuration: const Duration(hours: 1),
        );
      } else {
        _currentProject = _currentProject!.addVideoClip(imageClip);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _exportError = 'Failed to load image: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Play/pause video
  Future<void> togglePlayback() async {
    // We allow playback even if no video controller exists (e.g., image-only project)

    if (_isPlaying) {
      await _previewController?.pause();
      _isPlaying = false;
      _stopTimelineClock();
      // Pause all audio overlays
      for (final p in _audioPlayers.values) {
        await p.pause();
      }
    } else {
      _isPlaying = true;
      _startTimelineClock();
      
      // Always run preview controller; volume depends on overlays at current time
      final clip = _clipAtTimeline(_currentPosition);
      if (clip != null) {
        if (clip.mediaType == MediaType.video && clip.videoFile != null) {
          // Ensure correct controller and position at start for video
          _switchActivePreviewController(clip.videoFile!.path);
          final offsetWithinClip = _currentPosition - clip.startTime;
          final sourcePosition = clip.sourceStart + offsetWithinClip;
          final dur = _previewController!.value.duration;
          // Avoid end-of-video exact seek which can hold last frame
          final frameEps = const Duration(milliseconds: 1);
          final almostEnd = dur > frameEps ? dur - frameEps : Duration.zero;
          final clamped = sourcePosition >= dur ? almostEnd : sourcePosition;
          await _previewController!.seekTo(clamped);
        } else {
          // Image clip: pause and mute any active video controller
          await _previewController?.pause();
          await _previewController?.setVolume(0.0);
        }
      }
      await _applyPreviewVolumeForCurrentPosition();
      if (_previewController != null && !_previewController!.value.isPlaying) {
        await _previewController!.play();
      }
    }
    _startPositionListener();
    // Start/sync audio overlays
    unawaited(_syncAudioPlayback());
    notifyListeners();
  }

  /// Video position listener
  void _videoPositionListener() {
    if (_previewController != null && _previewController!.value.isInitialized) {
      final position = _previewController!.value.position;
      // Map source position to timeline position if within any clip's source range
      final mappedTimelinePos = _mapSourceToTimeline(position);
      if (mappedTimelinePos != null && _isPlaying) {
        // Only update timeline position when video controller is actively playing a clip
        // Timeline clock handles position updates during gaps
        if (_isPositionInAnyClip(mappedTimelinePos)) {
          _currentPosition = mappedTimelinePos;
          _updateTimelineClock(); // Sync timeline clock with video position
          notifyListeners();
        }
      }
    }
  }

  /// Check if the given position is within any video clip
  /// Uses half-open interval [start, end) to avoid boundary ambiguity
  bool _isPositionInAnyClip(Duration position) {
    if (_currentProject == null) return false;
    
    // Use a small epsilon to avoid lingering on the last frame of the previous clip
    const eps = Duration(milliseconds: 5);
    return _currentProject!.videoClips.any((clip) => 
      // Prefer new clip when near its start
      ((position - clip.startTime).abs() <= eps) ||
      // Half-open with epsilon-shrunk end
      (position >= clip.startTime && position < (clip.endTime - eps))
    );
  }

  /// Handle playback during gaps between clips (black screen)
  void _handleBlackScreenPlayback(Duration position) {
    // Mute audio and pause video controller during gaps
    _previewController!.setVolume(0.0);
    _previewController!.pause();
    
    // Timeline clock will continue advancing the playhead
    // UI will show black screen during this gap
  }

  /// Apply preview volume for current timeline position
  /// Rules:
  /// - If any audio overlay is active at current position, mute video preview (0.0)
  /// - Else, if inside a video clip, set volume to that clip's volume (clamped 0..1)
  /// - Else (gap or image), mute
  Future<void> _applyPreviewVolumeForCurrentPosition() async {
    if (_previewController == null || _currentProject == null) return;

    final now = _currentPosition;

    // Always apply clip volume (mixed with overlays) so background video audio plays.
    double targetVolume = 0.0;
    final clip = _clipAtTimeline(now);
    if (clip != null && clip.mediaType == MediaType.video) {
      final clipVol = clip.volume;
      targetVolume = (clipVol * _videoMasterVolume).clamp(0.0, 1.0);
    }

    await _previewController!.setVolume(targetVolume);
  }

  /// Find the next clip after the given position
  VideoClip? _findNextClip(Duration position) {
    if (_currentProject == null || _currentProject!.videoClips.isEmpty) return null;
    
    VideoClip? nextClip;
    Duration minStartTime = const Duration(hours: 24);
    
    for (final clip in _currentProject!.videoClips) {
      if (clip.startTime > position && clip.startTime < minStartTime) {
        minStartTime = clip.startTime;
        nextClip = clip;
      }
    }
    
    return nextClip;
  }

  /// Start listening to video position updates
  void _startPositionListener() {
    _previewController?.addListener(_videoPositionListener);
  }

  /// Seek to specific position
  Future<void> seekTo(Duration position) async {
    // Allow seeking even without a video controller (image-only sequences)

    // Allow seeking anywhere in the full 60-minute timeline
    _currentPosition = position;
    _updateTimelineClock(); // Update timeline clock to new position
    
    // If seeking to a gap or beyond mapped regions, mute audio and keep preview running
    final clip = _clipAtTimeline(position);
    if (clip == null) {
      // In gap - keep controller playing (muted)
      if (_previewController != null) {
        await _previewController!.setVolume(0.0);
        if (_isPlaying && !_previewController!.value.isPlaying) {
          await _previewController!.play();
        }
      }
    } else {
      if (clip.mediaType == MediaType.image) {
        // Image: pause/mute video controller; UI will render the image
        await _previewController?.pause();
        await _previewController?.setVolume(0.0);
      } else if (clip.mediaType == MediaType.video && clip.videoFile != null) {
        // Map timeline position to source position
        final offsetWithinClip = position - clip.startTime;
        final sourcePosition = clip.sourceStart + offsetWithinClip;
        // Switch to the appropriate controller for this clip
        _switchActivePreviewController(clip.videoFile!.path);
        final videoDuration = _previewController!.value.duration;
        
        // If source position is beyond video duration, treat as gap
        if (sourcePosition >= videoDuration) {
          await _previewController!.pause();
          await _previewController!.setVolume(0.0);
        } else {
          final clampedSource = sourcePosition > videoDuration ? videoDuration : sourcePosition;
          await _previewController!.seekTo(clampedSource);
          await _applyPreviewVolumeForCurrentPosition();
          
          // If playing, ensure video controller is playing
          if (_isPlaying && !_previewController!.value.isPlaying) {
            await _previewController!.play();
          }
        }
      }
    }
    
    // Sync audio overlays to new position
    await _syncAudioPlayback();

    notifyListeners();
  }

  /// Map a source (controller) position to a timeline position if within any clip's source range
  Duration? _mapSourceToTimeline(Duration sourcePosition) {
    if (_currentProject == null) return null;
    // Only consider clips that belong to the active file
    final activePath = _activeFilePath;
    if (activePath == null) return null;
    // Prefer clip whose source starts exactly at this position (with epsilon)
    const eps = Duration(milliseconds: 5);
    for (final clip in _currentProject!.videoClips) {
      if (clip.mediaType != MediaType.video || clip.videoFile == null) continue;
      if (clip.videoFile!.path != activePath) continue;
      if ((sourcePosition - clip.sourceStart).abs() <= eps) {
        return clip.startTime;
      }
    }
    // Otherwise, use half-open interval [sourceStart, sourceEnd) with epsilon-shrunk end
    for (final clip in _currentProject!.videoClips) {
      if (clip.mediaType != MediaType.video || clip.videoFile == null) continue;
      if (clip.videoFile!.path != activePath) continue;
      if (sourcePosition >= clip.sourceStart && sourcePosition < (clip.sourceEnd - eps)) {
        final offset = sourcePosition - clip.sourceStart;
        return clip.startTime + offset;
      }
    }
    return null;
  }

  /// Find clip at a given timeline position
  /// Boundary rule: if position equals a clip's start, prefer that clip.
  /// Otherwise use half-open interval [start, end) for containment.
  VideoClip? _clipAtTimeline(Duration position) {
    if (_currentProject == null) return null;
    // Use a small epsilon to bias towards the next clip at boundaries
    const eps = Duration(milliseconds: 5);
    // Prefer a clip whose start is within epsilon of the position
    for (final clip in _currentProject!.videoClips) {
      if ((position - clip.startTime).abs() <= eps) return clip;
    }
    // Otherwise, find clip containing position with exclusive end (shrunk by eps)
    for (final clip in _currentProject!.videoClips) {
      if (position >= clip.startTime && position < (clip.endTime - eps)) return clip;
    }
    return null;
  }

  /// Find the nearest clip to a given position
  VideoClip? _findNearestClip(Duration position) {
    if (_currentProject == null || _currentProject!.videoClips.isEmpty) return null;
    
    VideoClip? nearestClip;
    Duration minDistance = const Duration(hours: 24);
    
    for (final clip in _currentProject!.videoClips) {
      final distanceToStart = (position - clip.startTime).abs();
      final distanceToEnd = (position - clip.endTime).abs();
      final minClipDistance = distanceToStart < distanceToEnd ? distanceToStart : distanceToEnd;
      
      if (minClipDistance < minDistance) {
        minDistance = minClipDistance;
        nearestClip = clip;
      }
    }
    
    return nearestClip;
  }

  /// Update position (for manual seeking)
  void updatePosition(Duration position) {
    _currentPosition = position;
    _updateTimelineClock();
    notifyListeners();
  }

  /// Trim video clip
  Future<void> trimVideoClip(String clipId, Duration startTrim, Duration endTrim) async {
    if (_currentProject == null) return;

    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(
      trimStart: startTrim,
      trimEnd: endTrim,
    );

    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
    notifyListeners();
  }

  /// Crop video clip
  Future<void> cropVideoClip(String clipId, Rect cropRect) async {
    if (_currentProject == null) return;

    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(cropRect: cropRect);

    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
    notifyListeners();
  }

  /// Update video clip volume
  Future<void> updateVideoClipVolume(String clipId, double volume) async {
    if (_currentProject == null) return;

    // Clamp volume
    final newVol = volume.clamp(0.0, 1.0);
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updated = clip.copyWith(volume: newVol);
    _currentProject = _currentProject!.updateVideoClip(clipId, updated);

    // If the playhead is within this clip and no audio overlay is active, apply preview volume
    await _applyPreviewVolumeForCurrentPosition();
    notifyListeners();
  }

  /// Rotate video clip
  Future<void> rotateVideoClip(String clipId, double rotation) async {
    if (_currentProject == null) return;

    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(rotation: rotation);

    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
    notifyListeners();
  }

  /// Add text overlay
  Future<void> addTextOverlay({
    required String text,
    required Offset position,
    required Duration startTime,
    required Duration endTime,
    double fontSize = 24.0,
    Color color = Colors.white,
    String fontFamily = 'Roboto',
    FontWeight fontWeight = FontWeight.normal,
  }) async {
    if (_currentProject == null) return;

    final overlay = TextOverlay(
      id: _uuid.v4(),
      text: text,
      position: position,
      fontSize: fontSize,
      color: color,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      startTime: startTime,
      endTime: endTime,
    );

    _currentProject = _currentProject!.addTextOverlay(overlay);
    notifyListeners();
  }

  /// Update text overlay
  Future<void> updateTextOverlay(String overlayId, {
    String? text,
    Offset? position,
    double? fontSize,
    Color? color,
    String? fontFamily,
    FontWeight? fontWeight,
    Duration? startTime,
    Duration? endTime,
    double? rotation,
    double? opacity,
  }) async {
    if (_currentProject == null) return;

    final overlay = _currentProject!.textOverlays.firstWhere((o) => o.id == overlayId);
    final updatedOverlay = overlay.copyWith(
      text: text,
      position: position,
      fontSize: fontSize,
      color: color,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      startTime: startTime,
      endTime: endTime,
      rotation: rotation,
      opacity: opacity,
    );

    _currentProject = _currentProject!.updateTextOverlay(overlayId, updatedOverlay);
    notifyListeners();
  }

  /// Remove text overlay
  Future<void> removeTextOverlay(String overlayId) async {
    if (_currentProject == null) return;

    _currentProject = _currentProject!.removeTextOverlay(overlayId);
    if (_selectedTextOverlayId == overlayId) {
      _selectedTextOverlayId = null;
    }
    notifyListeners();
  }

  /// Add audio overlay
  Future<void> addAudioOverlay({
    required File audioFile,
    required Duration startTime,
    required Duration endTime,
    Duration audioStartOffset = Duration.zero,
    double volume = 1.0,
    bool fadeIn = false,
    bool fadeOut = false,
  }) async {
    if (_currentProject == null) return;

    final overlay = AudioOverlay(
      id: _uuid.v4(),
      audioFile: audioFile,
      startTime: startTime,
      endTime: endTime,
      audioStartOffset: audioStartOffset,
      volume: volume,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
    );

    _currentProject = _currentProject!.addAudioOverlay(overlay);
    notifyListeners();
  }

  /// Update audio overlay
  Future<void> updateAudioOverlay(String overlayId, {
    Duration? startTime,
    Duration? endTime,
    Duration? audioStartOffset,
    double? volume,
    bool? fadeIn,
    bool? fadeOut,
  }) async {
    if (_currentProject == null) return;

    final overlay = _currentProject!.audioOverlays.firstWhere((o) => o.id == overlayId);
    final updatedOverlay = overlay.copyWith(
      startTime: startTime,
      endTime: endTime,
      audioStartOffset: audioStartOffset,
      volume: volume,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
    );

    _currentProject = _currentProject!.updateAudioOverlay(overlayId, updatedOverlay);
    // Update player properties if exists
    final player = _audioPlayers[overlayId];
    if (player != null) {
      if (volume != null) {
        await player.setVolume(volume);
      }
      // If playing, re-sync position
      if (_isPlaying) {
        unawaited(_syncAudioPlayback());
      }
    }
    notifyListeners();
  }

  /// Remove audio overlay
  Future<void> removeAudioOverlay(String overlayId) async {
    if (_currentProject == null) return;

    _currentProject = _currentProject!.removeAudioOverlay(overlayId);
    if (_selectedAudioOverlayId == overlayId) {
      _selectedAudioOverlayId = null;
    }
    // Dispose and remove player
    final player = _audioPlayers.remove(overlayId);
    await player?.dispose();
    notifyListeners();
  }

  /// Cut audio overlay at current position
  void cutAudioOverlay(String overlayId) {
    if (_currentProject == null) return;

    final index = _currentProject!.audioOverlays.indexWhere((o) => o.id == overlayId);
    if (index == -1) return;

    final original = _currentProject!.audioOverlays[index];
    final cutPosition = _currentPosition;

    // Don't cut if position is at the start or end of this overlay
    if (cutPosition <= original.startTime || cutPosition >= original.endTime) return;

    // Calculate how far into the overlay the cut is, to adjust the source offset for the second part
    final firstDuration = cutPosition - original.startTime;
    final secondOffset = original.audioStartOffset + firstDuration;

    final firstPart = AudioOverlay(
      id: _uuid.v4(),
      audioFile: original.audioFile,
      startTime: original.startTime,
      endTime: cutPosition,
      audioStartOffset: original.audioStartOffset,
      volume: original.volume,
      fadeIn: original.fadeIn,
      fadeOut: false, // fade out resets on split
    );

    final secondPart = AudioOverlay(
      id: _uuid.v4(),
      audioFile: original.audioFile,
      startTime: cutPosition,
      endTime: original.endTime,
      audioStartOffset: secondOffset,
      volume: original.volume,
      fadeIn: false, // fade in resets on split
      fadeOut: original.fadeOut,
    );

    final overlays = List<AudioOverlay>.from(_currentProject!.audioOverlays);
    overlays.removeAt(index);
    overlays.insert(index, firstPart);
    overlays.insert(index + 1, secondPart);

    _currentProject = _currentProject!.copyWith(audioOverlays: overlays);

    // Update selection to the second part for immediate user feedback
    _selectedAudioOverlayId = secondPart.id;

    // Dispose old player's resources if it existed
    final oldPlayer = _audioPlayers.remove(overlayId);
    unawaited(oldPlayer?.dispose());

    // Re-sync audio playback players to reflect new overlays if currently playing
    if (_isPlaying) {
      unawaited(_syncAudioPlayback());
    }
    notifyListeners();
  }

  /// Apply color filter
  Future<void> applyColorFilter(ColorFilter filter) async {
    if (_currentProject == null) return;

    _currentProject = _currentProject!.copyWith(colorFilter: filter);
    notifyListeners();
  }

  /// Export video
  Future<String?> exportVideo({
    required String outputPath,
    Function(double)? onProgress,
  }) async {
    if (_currentProject == null || _videoController == null) return null;

    try {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportError = null;
      notifyListeners();

      // Simulate export progress for now
      for (int i = 0; i <= 100; i += 10) {
        await Future.delayed(const Duration(milliseconds: 200));
        _exportProgress = i / 100.0;
        onProgress?.call(_exportProgress);
        notifyListeners();
      }

      // For now, copy the first available video clip's file to the output path
      // In a real implementation, this would render the full timeline with edits
      final firstVideo = _currentProject!.videoClips.firstWhere(
        (c) => c.mediaType == MediaType.video && c.videoFile != null,
        orElse: () => _currentProject!.videoClips.isNotEmpty ? _currentProject!.videoClips.first : throw StateError('No clips'),
      );
      if (firstVideo.mediaType != MediaType.video || firstVideo.videoFile == null) {
        throw StateError('No video clips available to export');
      }
      final originalFile = firstVideo.videoFile!;
      await originalFile.copy(outputPath);

      _isExporting = false;
      _exportProgress = 1.0;
      notifyListeners();
      
      return outputPath;
    } catch (e) {
      _isExporting = false;
      _exportError = 'Export failed: $e';
      notifyListeners();
      return null;
    }
  }

  /// UI State Management
  void toggleTimeline() {
    _showTimeline = !_showTimeline;
    if (_showTimeline) {
      _showFilters = false;
      _showTextEditor = false;
      _showAudioEditor = false;
      _showCropEditor = false;
      _showRotateEditor = false;
    }
    notifyListeners();
  }

  void toggleFilters() {
    _showFilters = !_showFilters;
    if (_showFilters) {
      _showTimeline = false;
      _showTextEditor = false;
      _showAudioEditor = false;
      _showCropEditor = false;
      _showRotateEditor = false;
    }
    notifyListeners();
  }

  void toggleTextEditor() {
    _showTextEditor = !_showTextEditor;
    if (_showTextEditor) {
      _showTimeline = false;
      _showFilters = false;
      _showAudioEditor = false;
      _showCropEditor = false;
      _showRotateEditor = false;
    }
    notifyListeners();
  }

  void toggleAudioEditor() {
    _showAudioEditor = !_showAudioEditor;
    if (_showAudioEditor) {
      _showTimeline = false;
      _showFilters = false;
      _showTextEditor = false;
      _showCropEditor = false;
      _showRotateEditor = false;
    }
    notifyListeners();
  }

  void toggleCropEditor() {
    _showCropEditor = !_showCropEditor;
    if (_showCropEditor) {
      _showTimeline = false;
      _showFilters = false;
      _showTextEditor = false;
      _showAudioEditor = false;
      _showRotateEditor = false;
    }
    notifyListeners();
  }

  void toggleRotateEditor() {
    _showRotateEditor = !_showRotateEditor;
    if (_showRotateEditor) {
      _showTimeline = false;
      _showFilters = false;
      _showTextEditor = false;
      _showAudioEditor = false;
      _showCropEditor = false;
    }
    notifyListeners();
  }

  // Update text overlay position when dragged
  Future<void> updateTextOverlayPosition(String overlayId, Offset newPosition) async {
    if (_currentProject == null) return;

    final overlayIndex = _currentProject!.textOverlays.indexWhere((o) => o.id == overlayId);
    if (overlayIndex == -1) return;

    final overlay = _currentProject!.textOverlays[overlayIndex];
    final updatedOverlay = overlay.copyWith(position: newPosition);

    _currentProject = _currentProject!.updateTextOverlay(overlayId, updatedOverlay);
    notifyListeners();
  }

  // Move text overlay in timeline
  Future<void> moveTextOverlay(String overlayId, Duration newStartTime) async {
    if (_currentProject == null) return;

    final overlayIndex = _currentProject!.textOverlays.indexWhere((o) => o.id == overlayId);
    if (overlayIndex == -1) return;

    final overlay = _currentProject!.textOverlays[overlayIndex];
    final duration = overlay.endTime - overlay.startTime;
    final newEndTime = newStartTime + duration;

    // Ensure duration doesn't exceed 300 seconds
    final clampedDuration = duration.inSeconds > 300 ? const Duration(seconds: 300) : duration;
    final clampedEndTime = newStartTime + clampedDuration;

    final updatedOverlay = overlay.copyWith(
      startTime: newStartTime,
      endTime: clampedEndTime,
    );

    _currentProject = _currentProject!.updateTextOverlay(overlayId, updatedOverlay);
    notifyListeners();
  }

  void selectTextOverlay(String? overlayId) {
    _selectedTextOverlayId = overlayId;
    notifyListeners();
  }

  void selectAudioOverlay(String? overlayId) {
    _selectedAudioOverlayId = overlayId;
    notifyListeners();
  }

  void selectVideoClip(String? clipId) {
    _selectedVideoClipId = clipId;
    notifyListeners();
  }

  /// Get text overlays at current position
  List<TextOverlay> get currentTextOverlays {
    if (_currentProject == null) return [];
    return _currentProject!.getTextOverlaysAtTime(_currentPosition);
  }

  /// Get audio overlays at current position
  List<AudioOverlay> get currentAudioOverlays {
    if (_currentProject == null) return [];
    return _currentProject!.getAudioOverlaysAtTime(_currentPosition);
  }

  /// Check if current position is in a gap (should show black screen)
  bool get isInGap {
    if (!_isPositionInAnyClip(_currentPosition)) return true;

    final clip = _clipAtTimeline(_currentPosition);
    if (clip == null) return true;
    // Image clips are never considered gaps while active
    if (clip.mediaType == MediaType.image) return false;

    // For video, verify source position is within the controller duration
    if (clip.mediaType == MediaType.video && clip.videoFile != null) {
      const eps = Duration(milliseconds: 5);
      final offsetWithinClip = _currentPosition - clip.startTime;
      final sourcePosition = clip.sourceStart + offsetWithinClip;
      final path = clip.videoFile!.path;
      final controller = _previewControllers[path];
      final dur = controller?.value.duration ?? Duration.zero;
      // Treat near-end as outside to bias transition to next clip
      return sourcePosition >= (dur - eps);
    }

    return true;
  }

  /// Get current video clip at position
  VideoClip? get currentVideoClip {
    return _clipAtTimeline(_currentPosition);
  }

  /// Reset controllers
  void _resetControllers() {
    _videoController = null;
    _previewController = null;
    _activeFilePath = null;
    for (final c in _previewControllers.values) {
      // will be disposed in _disposeControllers
    }
    _previewControllers.clear();
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _selectedTextOverlayId = null;
    _selectedAudioOverlayId = null;
    _selectedVideoClipId = null;
  }

  /// Dispose controllers
  Future<void> _disposeControllers() async {
    _stopTimelineClock();
    _previewController?.removeListener(_videoPositionListener);
    await _videoController?.dispose();
    // Dispose all preview controllers
    for (final c in _previewControllers.values) {
      await c.dispose();
    }
    _previewControllers.clear();
    _activeFilePath = null;
    // Dispose audio players
    for (final p in _audioPlayers.values) {
      await p.dispose();
    }
    _audioPlayers.clear();
    _resetControllers();
  }

  /// Start timeline clock for continuous playback
  void _startTimelineClock() {
    _stopTimelineClock();
    _playbackStartTime = DateTime.now();
    _playbackStartPosition = _currentPosition;
    
    _timelineTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      
      final elapsed = DateTime.now().difference(_playbackStartTime!);
      final newPosition = _playbackStartPosition! + elapsed;
      
      // Clamp to project end (end of last clip)
      if (newPosition >= projectDuration) {
        _currentPosition = projectDuration;
        _isPlaying = false;
        _stopTimelineClock();
        _previewController?.pause();
      } else {
        _currentPosition = newPosition;
        _handleTimelineAdvance();
      }
      
      notifyListeners();
    });
  }
  
  /// Stop timeline clock
  void _stopTimelineClock() {
    _timelineTimer?.cancel();
    _timelineTimer = null;
    _playbackStartTime = null;
    _playbackStartPosition = null;
  }
  
  /// Update timeline clock to sync with current position
  void _updateTimelineClock() {
    if (_isPlaying && _timelineTimer != null) {
      _playbackStartTime = DateTime.now();
      _playbackStartPosition = _currentPosition;
    }
  }
  
  /// Handle timeline advance during playback
  void _handleTimelineAdvance() {
    final currentClip = _clipAtTimeline(_currentPosition);
    final previousPos = _currentPosition - const Duration(milliseconds: 16);
    final previousClip = _clipAtTimeline(previousPos);

    if (currentClip != null && (previousClip == null || previousClip.id != currentClip.id)) {
      // Entered a new clip (either from gap or from a different clip)
      _enterClip(currentClip);
    } else if (currentClip == null && previousClip != null) {
      // Left a clip into a gap
      _leaveClip();
    }

    // Epsilon boundary handling: if close to a clip start, ensure we enter it
    const boundaryEps = Duration(milliseconds: 50);
    if (currentClip == null && _currentProject != null) {
      VideoClip? nearStart;
      for (final c in _currentProject!.videoClips) {
        final diff = (_currentPosition - c.startTime).abs();
        if (diff <= boundaryEps) {
          if (nearStart == null || c.startTime < nearStart.startTime) {
            nearStart = c;
          }
        }
      }
      if (nearStart != null) {
        _enterClip(nearStart);
      }
    }

    // Adjust preview volume based on overlays at the new position
    unawaited(_applyPreviewVolumeForCurrentPosition());
    // Keep audio overlays in sync during playback
    unawaited(_syncAudioPlayback());
  }

  /// Handle entering a clip during playback
  void _enterClip(VideoClip clip) async {
    if (clip.mediaType == MediaType.image) {
      // For images, pause/mute any video controller; UI displays the image
      await _previewController?.pause();
      await _previewController?.setVolume(0.0);
      return;
    }

    // Video: ensure we are previewing with the correct source controller
    if (clip.videoFile != null) {
      _switchActivePreviewController(clip.videoFile!.path);
    }

    final offsetWithinClip = _currentPosition - clip.startTime;
    final sourcePosition = clip.sourceStart + offsetWithinClip;
    final videoDuration = _previewController!.value.duration;
    
    // If source position is beyond video duration, treat as gap
    if (sourcePosition >= videoDuration) {
      await _previewController!.pause();
      await _previewController!.setVolume(0.0);
      return;
    }
    
    // Avoid seeking exactly to the very end which can freeze the last frame
    final frameEps = const Duration(milliseconds: 1);
    final almostEnd = videoDuration > frameEps ? videoDuration - frameEps : Duration.zero;
    final clampedSource = sourcePosition >= videoDuration ? almostEnd : sourcePosition;
    
    await _previewController!.seekTo(clampedSource);
    await _applyPreviewVolumeForCurrentPosition();
    if (!_previewController!.value.isPlaying) {
      await _previewController!.play();
    }
  }
  
  /// Handle leaving a clip during playback
  void _leaveClip() async {
    await _previewController!.setVolume(0.0);
    // Keep controller playing; we'll seek/unmute on entering next clip
  }
  
  /// Handle playback in gaps
  void _handleGapPlayback() {
    // Timeline clock will continue advancing
    // Video controller stays paused and muted
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  /// Ensure audio overlays are playing/paused in sync with current position
  Future<void> _syncAudioPlayback() async {
    if (_currentProject == null) return;

    final now = _currentPosition;
    for (final overlay in _currentProject!.audioOverlays) {
      final active = now >= overlay.startTime && now < overlay.endTime;
      final id = overlay.id;
      // Lazily create player
      var player = _audioPlayers[id];
      if (player == null) {
        player = AudioPlayer();
        _audioPlayers[id] = player;
        await player.setVolume(overlay.volume);
        await player.setFilePath(overlay.audioFile.path);
      }

      // Always ensure the player's volume reflects the latest overlay volume
      // combined with the audio master volume so live changes take effect.
      final effectiveOverlayVolume = (overlay.volume * _audioMasterVolume).clamp(0.0, 1.0);
      await player.setVolume(effectiveOverlayVolume);

      if (!active || !_isPlaying) {
        if (player.playing) {
          await player.pause();
        }
        continue;
      }

      // Compute audio position relative to source
      final elapsedInOverlay = now - overlay.startTime;
      final audioPos = overlay.audioStartOffset + elapsedInOverlay;

      // If not playing or out of sync, seek and play
      final tolerance = const Duration(milliseconds: 100);
      final pos = await player.position;
      if (!player.playing || (pos - audioPos).abs() > tolerance) {
        await player.seek(audioPos);
        await player.play();
      }
    }

    // Pause players for overlays that no longer exist
    final validIds = _currentProject!.audioOverlays.map((o) => o.id).toSet();
    for (final entry in _audioPlayers.entries.toList()) {
      if (!validIds.contains(entry.key)) {
        await entry.value.dispose();
        _audioPlayers.remove(entry.key);
      }
    }
  }
}
