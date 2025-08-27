import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';

class FilterEditor extends StatefulWidget {
  const FilterEditor({super.key});

  @override
  State<FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends State<FilterEditor> {
  late ColorFilter _currentFilter;

  @override
  void initState() {
    super.initState();
    _currentFilter = const ColorFilter();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        // Update current filter from provider
        if (provider.currentProject != null) {
          _currentFilter = provider.currentProject!.colorFilter;
        }

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(provider),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildFilterControls(provider),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _buildPresetFilters(provider),
                    ),
                  ],
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
          'Color & Filter Editor',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => _resetFilters(provider),
          child: const Text('Reset All'),
        ),
        ElevatedButton(
          onPressed: () => _applyFilters(provider),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _buildFilterControls(VideoEditorProvider provider) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Color Adjustments',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildSliderControl(
                      'Brightness',
                      _currentFilter.brightness,
                      -1.0,
                      1.0,
                      (value) => _updateFilter(_currentFilter.copyWith(brightness: value)),
                      Icons.brightness_6,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Contrast',
                      _currentFilter.contrast,
                      0.0,
                      2.0,
                      (value) => _updateFilter(_currentFilter.copyWith(contrast: value)),
                      Icons.contrast,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Saturation',
                      _currentFilter.saturation,
                      0.0,
                      2.0,
                      (value) => _updateFilter(_currentFilter.copyWith(saturation: value)),
                      Icons.palette,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Hue',
                      _currentFilter.hue,
                      -180.0,
                      180.0,
                      (value) => _updateFilter(_currentFilter.copyWith(hue: value)),
                      Icons.color_lens,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Exposure',
                      _currentFilter.exposure,
                      -2.0,
                      2.0,
                      (value) => _updateFilter(_currentFilter.copyWith(exposure: value)),
                      Icons.exposure,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Highlights',
                      _currentFilter.highlights,
                      -1.0,
                      1.0,
                      (value) => _updateFilter(_currentFilter.copyWith(highlights: value)),
                      Icons.highlight,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Shadows',
                      _currentFilter.shadows,
                      -1.0,
                      1.0,
                      (value) => _updateFilter(_currentFilter.copyWith(shadows: value)),
                      Icons.brightness_low,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Warmth',
                      _currentFilter.warmth,
                      -1.0,
                      1.0,
                      (value) => _updateFilter(_currentFilter.copyWith(warmth: value)),
                      Icons.wb_sunny,
                    ),
                    const SizedBox(height: 16),
                    _buildSliderControl(
                      'Tint',
                      _currentFilter.tint,
                      -1.0,
                      1.0,
                      (value) => _updateFilter(_currentFilter.copyWith(tint: value)),
                      Icons.gradient,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderControl(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              '$label: ${value.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            if (value != (label == 'Contrast' || label == 'Saturation' ? 1.0 : 0.0))
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.grey, size: 16),
                onPressed: () => onChanged(label == 'Contrast' || label == 'Saturation' ? 1.0 : 0.0),
                tooltip: 'Reset',
              ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.purple,
            inactiveTrackColor: Colors.grey[600],
            thumbColor: Colors.purple,
            overlayColor: Colors.blue.withOpacity(0.2),
            trackHeight: 4.0,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPresetFilters(VideoEditorProvider provider) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter Presets',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildPresetCard('Original', const ColorFilter(), provider),
                    _buildPresetCard('Vintage', _getVintageFilter(), provider),
                    _buildPresetCard('Warm', _getWarmFilter(), provider),
                    _buildPresetCard('Cool', _getCoolFilter(), provider),
                    _buildPresetCard('High Contrast', _getHighContrastFilter(), provider),
                    _buildPresetCard('Soft', _getSoftFilter(), provider),
                    _buildPresetCard('Dramatic', _getDramaticFilter(), provider),
                    _buildPresetCard('Black & White', _getBlackWhiteFilter(), provider),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetCard(String name, ColorFilter filter, VideoEditorProvider provider) {
    final isSelected = _filtersEqual(_currentFilter, filter);
    
    return SizedBox(
      width: 80,
      height: 80,
      child: GestureDetector(
        onTap: () => _applyPresetFilter(filter, provider),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.purple[700] : Colors.grey[700],
            borderRadius: BorderRadius.circular(6),
            border: isSelected ? Border.all(color: Colors.purple, width: 2) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _getFilterPreviewColor(filter),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  name,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[300],
                    fontSize: 9,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getFilterPreviewColor(ColorFilter filter) {
    // Generate a preview color based on filter settings
    double r = 0.5 + filter.brightness * 0.3;
    double g = 0.5 + filter.warmth * 0.2;
    double b = 0.5 - filter.warmth * 0.2 + filter.tint * 0.1;
    
    r = (r * filter.contrast * filter.saturation).clamp(0.0, 1.0);
    g = (g * filter.contrast * filter.saturation).clamp(0.0, 1.0);
    b = (b * filter.contrast * filter.saturation).clamp(0.0, 1.0);
    
    return Color.fromRGBO((r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt(), 1.0);
  }

  bool _filtersEqual(ColorFilter a, ColorFilter b) {
    return a.brightness == b.brightness &&
           a.contrast == b.contrast &&
           a.saturation == b.saturation &&
           a.hue == b.hue &&
           a.exposure == b.exposure &&
           a.highlights == b.highlights &&
           a.shadows == b.shadows &&
           a.warmth == b.warmth &&
           a.tint == b.tint;
  }

  void _updateFilter(ColorFilter newFilter) {
    setState(() {
      _currentFilter = newFilter;
    });
    // Apply filter immediately for real-time preview
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    provider.applyColorFilter(newFilter);
  }

  void _applyPresetFilter(ColorFilter filter, VideoEditorProvider provider) {
    setState(() {
      _currentFilter = filter;
    });
    _applyFilters(provider);
  }

  void _applyFilters(VideoEditorProvider provider) {
    provider.applyColorFilter(_currentFilter);
  }

  void _resetFilters(VideoEditorProvider provider) {
    setState(() {
      _currentFilter = const ColorFilter();
    });
    _applyFilters(provider);
  }

  // Preset filter definitions
  ColorFilter _getVintageFilter() {
    return const ColorFilter(
      brightness: 0.1,
      contrast: 1.2,
      saturation: 0.8,
      warmth: 0.3,
      shadows: 0.2,
    );
  }

  ColorFilter _getWarmFilter() {
    return const ColorFilter(
      warmth: 0.4,
      brightness: 0.05,
      contrast: 1.1,
    );
  }

  ColorFilter _getCoolFilter() {
    return const ColorFilter(
      warmth: -0.3,
      tint: 0.1,
      contrast: 1.05,
    );
  }

  ColorFilter _getHighContrastFilter() {
    return const ColorFilter(
      contrast: 1.5,
      brightness: 0.1,
      saturation: 1.2,
    );
  }

  ColorFilter _getSoftFilter() {
    return const ColorFilter(
      contrast: 0.8,
      brightness: 0.05,
      highlights: -0.2,
      shadows: 0.1,
    );
  }

  ColorFilter _getDramaticFilter() {
    return const ColorFilter(
      contrast: 1.4,
      saturation: 1.3,
      shadows: 0.3,
      highlights: -0.2,
    );
  }

  ColorFilter _getBlackWhiteFilter() {
    return const ColorFilter(
      saturation: 0.0,
      contrast: 1.2,
      brightness: 0.05,
    );
  }
}
