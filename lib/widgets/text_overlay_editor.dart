import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';

class TextOverlayEditor extends StatefulWidget {
  const TextOverlayEditor({super.key});

  @override
  State<TextOverlayEditor> createState() => _TextOverlayEditorState();
}

class _TextOverlayEditorState extends State<TextOverlayEditor> {
  final TextEditingController _textController = TextEditingController();
  // Duration is controlled via a slider (in seconds)
  double _durationSeconds = 5.0;
  
  double _fontSize = 24.0;
  Color _textColor = Colors.white;
  double _opacity = 1.0;
  Offset _position = const Offset(100, 100);


  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        // Update fields if a text overlay is selected
        if (provider.selectedTextOverlayId != null) {
          final overlay = provider.currentProject!.textOverlays
              .firstWhere((o) => o.id == provider.selectedTextOverlayId);
          _updateFieldsFromOverlay(overlay);
        }

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(provider),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextEditor(provider),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: _buildStyleEditor(provider),
                      ),
                    ],
                  ),
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
          'Text Overlay Editor',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (provider.selectedTextOverlayId != null)
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteSelectedOverlay(provider),
            tooltip: 'Delete Text Overlay',
          ),
        ElevatedButton.icon(
          onPressed: () => _addTextOverlay(provider),
          icon: const Icon(Icons.add),
          label: const Text('Add Text'),
        ),
      ],
    );
  }

  Widget _buildTextEditor(VideoEditorProvider provider) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Text Content',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Enter your text here...',
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
              const SizedBox(height: 16),
              _buildDurationSlider(),
              const SizedBox(height: 16),
              _buildDragInstructions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duration: ${_formatDurationSeconds(_durationSeconds.toInt())} (Max: 5:00)',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Slider(
          value: _durationSeconds,
          min: 1,
          max: 300, // 5 minutes max
          divisions: 299,
          onChanged: (value) {
            setState(() {
              _durationSeconds = value;
            });
          },
          activeColor: Colors.blue,
        ),
      ],
    );
  }

  

  Widget _buildDragInstructions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.purple, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tip: You can drag text overlays directly on the video preview to reposition them!',
              style: TextStyle(color: Colors.purple, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleEditor(VideoEditorProvider provider) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Text Style',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildFontSizeSlider(),
              const SizedBox(height: 16),
              _buildColorPicker(),
              const SizedBox(height: 16),
              _buildOpacitySlider(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFontSizeSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Font Size: ${_fontSize.toInt()}px',
          style: const TextStyle(color: Colors.white),
        ),
        Slider(
          value: _fontSize,
          min: 12,
          max: 72,
          divisions: 60,
          onChanged: (value) {
            setState(() {
              _fontSize = value;
            });
          },
          activeColor: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildColorPicker() {
    final colors = [
      Colors.white,
      Colors.black,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Text Color',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: colors.map((color) {
            final isSelected = _textColor == color;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _textColor = color;
                  });
                },
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.purple, width: 3)
                            : Border.all(color: Colors.grey, width: 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        color == Colors.white ? 'White' : 'Black',
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.check, color: Colors.purple, size: 18),
                    ]
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }


  Widget _buildOpacitySlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opacity: ${(_opacity * 100).toInt()}%',
          style: const TextStyle(color: Colors.white),
        ),
        Slider(
          value: _opacity,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          onChanged: (value) {
            setState(() {
              _opacity = value;
            });
          },
          activeColor: Colors.purple,
        ),
      ],
    );
  }


  void _updateFieldsFromOverlay(TextOverlay overlay) {
    if (_textController.text != overlay.text) {
      _textController.text = overlay.text;
    }
    _fontSize = overlay.fontSize;
    _textColor = overlay.color;
    _opacity = overlay.opacity;
    _position = overlay.position;
    final duration = overlay.endTime - overlay.startTime;
    _durationSeconds = duration.inSeconds.toDouble().clamp(1.0, 300.0);
  }

  Future<void> _addTextOverlay(VideoEditorProvider provider) async {
    if (_textController.text.isEmpty) {
      _showErrorDialog('Please enter some text');
      return;
    }

    final startTime = provider.currentPosition; // Use current playhead position
    final endTime = startTime + Duration(seconds: _durationSeconds.toInt());

    if (startTime >= endTime) {
      _showErrorDialog('End time must be after current position');
      return;
    }

    await provider.addTextOverlay(
      text: _textController.text,
      position: _position,
      startTime: startTime,
      endTime: endTime,
      fontSize: _fontSize,
      color: _textColor,
      fontFamily: 'Roboto',
      fontWeight: FontWeight.normal,
    );

    _clearFields();
  }

  Future<void> _deleteSelectedOverlay(VideoEditorProvider provider) async {
    if (provider.selectedTextOverlayId != null) {
      await provider.removeTextOverlay(provider.selectedTextOverlayId!);
      _clearFields();
    }
  }

  void _clearFields() {
    _textController.clear();
    setState(() {
      _durationSeconds = 5.0;
      _fontSize = 24.0;
      _textColor = Colors.white;
      _opacity = 1.0;
      _position = const Offset(100, 100);
    });
  }

  String _formatDurationSeconds(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
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
