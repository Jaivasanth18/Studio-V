import 'dart:io';
import 'package:flutter/material.dart';

/// Media types supported by a timeline clip
enum MediaType { video, image }

/// Represents a text overlay on the video
class TextOverlay {
  final String id;
  final String text;
  final Offset position;
  final double fontSize;
  final Color color;
  final String fontFamily;
  final FontWeight fontWeight;
  final Duration startTime;
  final Duration endTime;
  final double rotation;
  final double opacity;

  TextOverlay({
    required this.id,
    required this.text,
    required this.position,
    this.fontSize = 24.0,
    this.color = Colors.white,
    this.fontFamily = 'Roboto',
    this.fontWeight = FontWeight.normal,
    required this.startTime,
    required this.endTime,
    this.rotation = 0.0,
    this.opacity = 1.0,
  });

  TextOverlay copyWith({
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
  }) {
    return TextOverlay(
      id: id,
      text: text ?? this.text,
      position: position ?? this.position,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
    );
  }
}

/// Represents an audio overlay on the video
class AudioOverlay {
  final String id;
  final File audioFile;
  final Duration startTime;
  final Duration endTime;
  final Duration audioStartOffset;
  final double volume;
  final bool fadeIn;
  final bool fadeOut;

  AudioOverlay({
    required this.id,
    required this.audioFile,
    required this.startTime,
    required this.endTime,
    this.audioStartOffset = Duration.zero,
    this.volume = 1.0,
    this.fadeIn = false,
    this.fadeOut = false,
  });

  AudioOverlay copyWith({
    File? audioFile,
    Duration? startTime,
    Duration? endTime,
    Duration? audioStartOffset,
    double? volume,
    bool? fadeIn,
    bool? fadeOut,
  }) {
    return AudioOverlay(
      id: id,
      audioFile: audioFile ?? this.audioFile,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      audioStartOffset: audioStartOffset ?? this.audioStartOffset,
      volume: volume ?? this.volume,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
    );
  }
}

/// Represents a media clip (video or image) in the timeline
class VideoClip {
  final String id;
  final MediaType mediaType;
  final File? videoFile; // present when mediaType == MediaType.video
  final File? imageFile; // present when mediaType == MediaType.image
  final Duration startTime;
  final Duration endTime;
  // New: source in/out within the original media
  final Duration sourceStart;
  final Duration sourceEnd;
  final Duration trimStart;
  final Duration trimEnd;
  final double volume;
  final bool isMuted;
  final double rotation;
  final Rect? cropRect;

  VideoClip({
    required this.id,
    required this.mediaType,
    this.videoFile,
    this.imageFile,
    required this.startTime,
    required this.endTime,
    Duration? sourceStart,
    Duration? sourceEnd,
    this.trimStart = Duration.zero,
    Duration? trimEnd,
    this.volume = 1.0,
    this.isMuted = false,
    this.rotation = 0.0,
    this.cropRect,
  })  : sourceStart = sourceStart ?? startTime,
        sourceEnd = sourceEnd ?? endTime,
        trimEnd = trimEnd ?? endTime;

  VideoClip copyWith({
    MediaType? mediaType,
    File? videoFile,
    File? imageFile,
    Duration? startTime,
    Duration? endTime,
    Duration? sourceStart,
    Duration? sourceEnd,
    Duration? trimStart,
    Duration? trimEnd,
    double? volume,
    bool? isMuted,
    double? rotation,
    Rect? cropRect,
  }) {
    return VideoClip(
      id: id,
      mediaType: mediaType ?? this.mediaType,
      videoFile: videoFile ?? this.videoFile,
      imageFile: imageFile ?? this.imageFile,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sourceStart: sourceStart ?? this.sourceStart,
      sourceEnd: sourceEnd ?? this.sourceEnd,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      rotation: rotation ?? this.rotation,
      cropRect: cropRect ?? this.cropRect,
    );
  }

  Duration get duration => endTime - startTime;
  Duration get trimmedDuration => trimEnd - trimStart;
}

/// Represents color filter settings
class ColorFilter {
  final double brightness;
  final double contrast;
  final double saturation;
  final double hue;
  final double exposure;
  final double highlights;
  final double shadows;
  final double warmth;
  final double tint;

  const ColorFilter({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.hue = 0.0,
    this.exposure = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.warmth = 0.0,
    this.tint = 0.0,
  });

  ColorFilter copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? hue,
    double? exposure,
    double? highlights,
    double? shadows,
    double? warmth,
    double? tint,
  }) {
    return ColorFilter(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      hue: hue ?? this.hue,
      exposure: exposure ?? this.exposure,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      warmth: warmth ?? this.warmth,
      tint: tint ?? this.tint,
    );
  }

  /// Check if any filter is applied
  bool get hasFilters {
    return brightness != 0.0 ||
        contrast != 1.0 ||
        saturation != 1.0 ||
        hue != 0.0 ||
        exposure != 0.0 ||
        highlights != 0.0 ||
        shadows != 0.0 ||
        warmth != 0.0 ||
        tint != 0.0;
  }
}

/// Main video project model containing all editing data
class VideoProject {
  final String id;
  final String name;
  final List<VideoClip> videoClips;
  final List<TextOverlay> textOverlays;
  final List<AudioOverlay> audioOverlays;
  final ColorFilter colorFilter;
  final Duration totalDuration;
  final Size outputResolution;
  final int outputFrameRate;
  final DateTime createdAt;
  final DateTime lastModified;

  VideoProject({
    required this.id,
    required this.name,
    this.videoClips = const [],
    this.textOverlays = const [],
    this.audioOverlays = const [],
    this.colorFilter = const ColorFilter(),
    this.totalDuration = Duration.zero,
    this.outputResolution = const Size(1920, 1080),
    this.outputFrameRate = 30,
    DateTime? createdAt,
    DateTime? lastModified,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModified = lastModified ?? DateTime.now();

  VideoProject copyWith({
    String? name,
    List<VideoClip>? videoClips,
    List<TextOverlay>? textOverlays,
    List<AudioOverlay>? audioOverlays,
    ColorFilter? colorFilter,
    Duration? totalDuration,
    Size? outputResolution,
    int? outputFrameRate,
    DateTime? lastModified,
  }) {
    return VideoProject(
      id: id,
      name: name ?? this.name,
      videoClips: videoClips ?? this.videoClips,
      textOverlays: textOverlays ?? this.textOverlays,
      audioOverlays: audioOverlays ?? this.audioOverlays,
      colorFilter: colorFilter ?? this.colorFilter,
      totalDuration: totalDuration ?? this.totalDuration,
      outputResolution: outputResolution ?? this.outputResolution,
      outputFrameRate: outputFrameRate ?? this.outputFrameRate,
      createdAt: createdAt,
      lastModified: lastModified ?? DateTime.now(),
    );
  }

  /// Calculate total project duration based on video clips
  Duration calculateTotalDuration() {
    if (videoClips.isEmpty) return Duration.zero;
    
    Duration maxEndTime = Duration.zero;
    for (final clip in videoClips) {
      if (clip.endTime > maxEndTime) {
        maxEndTime = clip.endTime;
      }
    }
    return maxEndTime;
  }

  /// Add a video clip to the project
  VideoProject addVideoClip(VideoClip clip) {
    final updatedClips = List<VideoClip>.from(videoClips)..add(clip);
    final newDuration = calculateTotalDuration();
    
    return copyWith(
      videoClips: updatedClips,
      totalDuration: newDuration,
      lastModified: DateTime.now(),
    );
  }

  /// Remove a video clip from the project
  VideoProject removeVideoClip(String clipId) {
    final updatedClips = videoClips.where((clip) => clip.id != clipId).toList();
    final newDuration = calculateTotalDuration();
    
    return copyWith(
      videoClips: updatedClips,
      totalDuration: newDuration,
      lastModified: DateTime.now(),
    );
  }

  /// Update a video clip in the project
  VideoProject updateVideoClip(String clipId, VideoClip updatedClip) {
    final updatedClips = videoClips.map((clip) {
      return clip.id == clipId ? updatedClip : clip;
    }).toList();
    final newDuration = calculateTotalDuration();
    
    return copyWith(
      videoClips: updatedClips,
      totalDuration: newDuration,
      lastModified: DateTime.now(),
    );
  }

  /// Add a text overlay to the project
  VideoProject addTextOverlay(TextOverlay overlay) {
    final updatedOverlays = List<TextOverlay>.from(textOverlays)..add(overlay);
    
    return copyWith(
      textOverlays: updatedOverlays,
      lastModified: DateTime.now(),
    );
  }

  /// Remove a text overlay from the project
  VideoProject removeTextOverlay(String overlayId) {
    final updatedOverlays = textOverlays.where((overlay) => overlay.id != overlayId).toList();
    
    return copyWith(
      textOverlays: updatedOverlays,
      lastModified: DateTime.now(),
    );
  }

  /// Update a text overlay in the project
  VideoProject updateTextOverlay(String overlayId, TextOverlay updatedOverlay) {
    final updatedOverlays = textOverlays.map((overlay) {
      return overlay.id == overlayId ? updatedOverlay : overlay;
    }).toList();
    
    return copyWith(
      textOverlays: updatedOverlays,
      lastModified: DateTime.now(),
    );
  }

  /// Add an audio overlay to the project
  VideoProject addAudioOverlay(AudioOverlay overlay) {
    final updatedOverlays = List<AudioOverlay>.from(audioOverlays)..add(overlay);
    
    return copyWith(
      audioOverlays: updatedOverlays,
      lastModified: DateTime.now(),
    );
  }

  /// Remove an audio overlay from the project
  VideoProject removeAudioOverlay(String overlayId) {
    final updatedOverlays = audioOverlays.where((overlay) => overlay.id != overlayId).toList();
    
    return copyWith(
      audioOverlays: updatedOverlays,
      lastModified: DateTime.now(),
    );
  }

  /// Update an audio overlay in the project
  VideoProject updateAudioOverlay(String overlayId, AudioOverlay updatedOverlay) {
    final updatedOverlays = audioOverlays.map((overlay) {
      return overlay.id == overlayId ? updatedOverlay : overlay;
    }).toList();
    
    return copyWith(
      audioOverlays: updatedOverlays,
      lastModified: DateTime.now(),
    );
  }

  /// Check if the project has any content
  bool get hasContent {
    return videoClips.isNotEmpty || textOverlays.isNotEmpty || audioOverlays.isNotEmpty;
  }

  /// Get all overlays at a specific time
  List<TextOverlay> getTextOverlaysAtTime(Duration time) {
    return textOverlays.where((overlay) {
      return time >= overlay.startTime && time <= overlay.endTime;
    }).toList();
  }

  /// Get all audio overlays at a specific time
  List<AudioOverlay> getAudioOverlaysAtTime(Duration time) {
    return audioOverlays.where((overlay) {
      return time >= overlay.startTime && time <= overlay.endTime;
    }).toList();
  }
}
