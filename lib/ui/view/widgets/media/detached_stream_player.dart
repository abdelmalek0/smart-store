import 'package:flutter/material.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/core/controllers/stream_playback_controller.dart';
import 'package:smart_store_linux/core/engine/pipeline_manager.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/ui/view/widgets/media/detection_overlay_painter.dart';

class DetachedStreamPlayer extends StatefulWidget {
  final String streamId;
  final bool showDebugInfo;

  const DetachedStreamPlayer({
    super.key,
    required this.streamId,
    this.showDebugInfo = true,
  });

  @override
  State<DetachedStreamPlayer> createState() => _DetachedStreamPlayerState();
}

class _DetachedStreamPlayerState extends State<DetachedStreamPlayer> {
  late StreamPlaybackController _controller;

  // Frame Logic
  int? _textureId;
  bool _isInitialized = false;

  // Render State (Synchronized Detections)
  List<dynamic> _currentDetections = [];
  int _currentFrameWidth = 1280;
  int _currentFrameHeight = 720;
  Map<int, String> _currentLabels = {};

  @override
  void initState() {
    super.initState();
    _controller = AppService.instance.streams.createPlaybackController(
      widget.streamId,
    );
    _controller.addListener(_onControllerStateChanged);
    // DON'T initialize here - wait until widget is actually visible
  }

  Future<void> _initializeController() async {
    if (_isInitialized) return;
    _isInitialized = true;

    debugPrint(
      "DetachedStreamPlayer: Initializing texture for ${widget.streamId} (now visible)",
    );

    // Ideally we get dimensions from the stream source or config
    // For now hardcoded or gathered from somewhere?
    // The previous code hardcoded 640x640 in multiple places or used defaults.
    await _controller.initialize(640, 640);
  }

  void _onControllerStateChanged() {
    if (mounted) {
      setState(() {
        _textureId = _controller.textureId;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerStateChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Initialize texture only when widget is actually built/visible
    if (!_isInitialized) {
      // Use post-frame callback to initialize after first paint
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isInitialized) {
          _initializeController();
        }
      });
    }

    if (_controller.error != null) {
      return Center(
        child: Text(
          "Error: ${_controller.error}",
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    // Subscribe to the detection stream (ProcessedFrame) which drives the loop
    return AnimatedBuilder(
      animation: PipelineManager.instance,
      builder: (context, child) {
        final pipeline = PipelineManager.instance.getPipeline(widget.streamId);

        if (pipeline == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 8),
                Text(
                  "Waiting for pipeline...",
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }

        return StreamBuilder<ProcessedFrame>(
          stream: pipeline.detectionStream,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final frame = snapshot.data!;
              _controller.onFrameTick(); // Maintenance

              // Trigger render
              _controller.showFrame(frame.decodeStartMs).then((success) {
                if (success && mounted) {
                  // Only update detections if we successfully showed the video frame
                  setState(() {
                    _currentDetections = frame.detections;
                    _currentFrameWidth = frame.width;
                    _currentFrameHeight = frame.height;
                    _currentLabels = pipeline.modelLabels;
                  });
                }
              });
            }

            return Stack(
              children: [
                // Video Layer
                Positioned.fill(
                  child: Container(
                    color: Colors.black,
                    child: _buildVideoContent(),
                  ),
                ),

                // Detections Overlay
                Positioned.fill(
                  child: CustomPaint(
                    painter: DetectionOverlayPainter(
                      detections: _currentDetections,
                      originalSize: Size(
                        _currentFrameWidth.toDouble(),
                        _currentFrameHeight.toDouble(),
                      ),
                      customLabels: _currentLabels,
                    ),
                  ),
                ),

                // Debug Stats
                if (widget.showDebugInfo)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "FPS: ${_controller.fps.toStringAsFixed(1)}\n"
                        "TexID: ${_textureId ?? 'None'}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildVideoContent() {
    if (_textureId != null) {
      return Texture(textureId: _textureId!);
    }
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}
