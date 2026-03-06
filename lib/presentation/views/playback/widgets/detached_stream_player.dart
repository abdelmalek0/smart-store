import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/application/blocs/playback/playback_bloc.dart';
import 'package:smart_store_linux/application/blocs/playback/playback_state.dart';
import 'package:smart_store_linux/application/controllers/stream_playback_controller.dart';
import 'package:smart_store_linux/application/engine/engine_orchestrator.dart';
import 'package:smart_store_linux/domain/entities/processed_frame.dart';
import 'package:smart_store_linux/presentation/views/playback/widgets/detection_overlay_painter.dart';

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
    _controller = StreamPlaybackController(widget.streamId);
    _controller.addListener(_onControllerStateChanged);
    // Initialization is deferred until the widget is visible (see build).
  }

  Future<void> _initializeController() async {
    if (_isInitialized) return;
    _isInitialized = true;

    debugPrint(
      "DetachedStreamPlayer: Initializing texture for ${widget.streamId} (now visible)",
    );

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
    if (!_isInitialized) {
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

    // BlocBuilder rebuilds when activePipelineIds changes (engine started/stopped).
    // This replaces the old AnimatedBuilder(animation: EngineOrchestrator.instance).
    return BlocBuilder<PlaybackBloc, PlaybackState>(
      buildWhen: (prev, curr) =>
          prev.isPipelineActive(widget.streamId) !=
          curr.isPipelineActive(widget.streamId),
      builder: (context, state) {
        final pipeline =
            EngineOrchestrator.instance.getPipeline(widget.streamId);

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
              _controller.onFrameTick();

              // Update detections synchronously so boxes and the video frame
              // are rendered in the same vsync pass.
              _currentDetections = frame.detections;
              _currentFrameWidth = frame.width;
              _currentFrameHeight = frame.height;
              _currentLabels = pipeline.modelLabels;

              _controller.showFrame(frame.decodeStartMs);
            }

            return Stack(
              children: [
                // Video Layer
                Positioned.fill(
                  child: Container(
                    color: Colors.black,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _currentFrameWidth.toDouble(),
                        height: _currentFrameHeight.toDouble(),
                        child: _buildVideoContent(),
                      ),
                    ),
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
