import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';
import 'package:smart_store_linux/core/engine/stream_engine.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/widgets/player/detection_overlay_painter.dart';
import 'package:smart_store_linux/ui/widgets/player/stats_overlay.dart';

import 'package:smart_store_linux/core/streaming/sync/stream_sync_manager.dart';
import 'package:smart_store_linux/core/resources/stream_stats_tracker.dart';

class DetachedStreamPlayer extends StatefulWidget {
  final String url;
  final String streamId;
  final String? modelPath;
  final String? label;

  const DetachedStreamPlayer({
    super.key,
    required this.url,
    required this.streamId,
    this.modelPath,
    this.label,
  });

  @override
  State<DetachedStreamPlayer> createState() => _DetachedStreamPlayerState();
}

class _DetachedStreamPlayerState extends State<DetachedStreamPlayer> {
  bool _isActive = true;

  // Delegates
  late final StreamSyncManager _syncManager;
  final StreamStatsTracker _statsTracker = StreamStatsTracker();

  // Display state
  ui.Image? _currentImage;
  List<dynamic> _currentDetections = [];
  int _currentWidth = 1920; // Default to full HD
  int _currentHeight = 1080;

  // Model labels from ONNX metadata (received from StreamPipeline)
  Map<int, String> _modelLabels = {};

  // User-uploaded custom labels (takes priority over _modelLabels)
  Map<int, String>? _userLabels;

  Timer? _fpsTimer;
  StreamSubscription? _frameSubscription;

  // Frame rate limiting - prevent UI thread overload
  ProcessedFrame? _pendingFrame;

  @override
  void initState() {
    super.initState();
    _syncManager = StreamSyncManager.create(widget.streamId);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_frameSubscription != null) return; // Already listening

    try {
      final externalProcessor = StreamEngine.instance.getPipeline(
        widget.streamId,
      );

      // Stream ID should be valid if we are here
      if (externalProcessor != null) {
        debugPrint("Attached to processor for ${widget.streamId}");

        // 1. Initial State Sync
        // Apply existing state if processor is already running
        if (mounted) {
          _updateLabels();

          setState(() {
            if (externalProcessor.frameWidth > 0) {
              _currentWidth = externalProcessor.frameWidth;
            }
            if (externalProcessor.frameHeight > 0) {
              _currentHeight = externalProcessor.frameHeight;
            }

            // Initial sync of android texture if already present
            _syncManager.updateTextureFromProcessor(externalProcessor);

            // Only use native labels if no user labels
            if (_userLabels == null &&
                externalProcessor.modelLabels.isNotEmpty) {
              _modelLabels = externalProcessor.modelLabels;
            }
          });
        }

        // 2. Linux Texture Creation (Platform Specific)
        await _syncManager.initialize(_currentWidth, _currentHeight);
        if (mounted && _syncManager.textureId != null) {
          setState(() {}); // Reflect texture creation
        }

        // 3. Subscribe to Stream
        // Crucial: We subscribe even if processor is not fully initialized.
        // This ensures we receive frames as soon as they start flowing.
        _frameSubscription = externalProcessor.frameStream.listen((
          frame,
        ) async {
          if (!mounted || !_isActive) return;

          bool needsSetState = false;

          // A. Late State Sync / Connection Logic
          if (_syncManager.updateTextureFromProcessor(externalProcessor)) {
            needsSetState = true;
          }

          // Linux: Connect stream to texture when Video ID becomes available
          await _syncManager.maintainConnection(externalProcessor);

          // Labels Sync - Check for user labels update from ModelProvider
          if (_updateLabels()) {
            needsSetState = true;
          }

          // Fall back to native labels if no user labels and native available
          if (_userLabels == null &&
              _modelLabels.isEmpty &&
              externalProcessor.modelLabels.isNotEmpty) {
            _modelLabels = externalProcessor.modelLabels;
            needsSetState = true;
          }

          if (needsSetState) {
            setState(() {});
          }

          // B. Strict Sync & Render Trigger
          // Pass timestamp to SyncManager to handle platform-specific showFrame logic
          final canRender = await _syncManager.showFrame(
            externalProcessor,
            frame.decodeStartMs,
          );

          if (!canRender) {
            // Frame dropped or missing in buffer - SKIP UI UPDATE
            // This enforces strict synchronization preventing overlay drift
            return;
          }

          // D. Update UI Data (FPS, Detections) - Optimized Path
          // Use Optimized Path if we are in Texture Mode (ignoring redundant bytes)
          // OR if we have no bytes (inference only)
          if (_syncManager.textureId != null || frame.imageBytes.isEmpty) {
            setState(() {
              _currentDetections = frame.detections;
              _currentWidth = frame.width;
              _currentHeight = frame.height;

              // FPS Calc
              _statsTracker.onFrameDisplayed();
              _statsTracker.updateTiming(frame.timingBreakdown);
            });
            return;
          }

          // Legacy/Fallback CPU Decode Path
          _decodeAndDisplayFrame(frame);
        });
      }
    } catch (e) {
      debugPrint("Error initializing player: $e");
    }
  }

  /// Helper to update labels from ModelProvider
  /// Returns [true] if labels changed
  bool _updateLabels() {
    if (!mounted) return false;

    // Get model path using same resolution logic as StreamPipeline
    String? effectiveModelPath = ConfigService.instance.getModelForStream(
      widget.streamId,
    );

    // Fallback to global plugin config if stream config not found
    if (effectiveModelPath == null) {
      final pluginId =
          ConfigService.instance.getStreamActivePlugin(widget.streamId) ??
          'people_counting';
      final globalConfig = ConfigService.instance.getGlobalPluginConfig(
        pluginId,
      );
      effectiveModelPath =
          globalConfig?['modelPath'] as String? ?? widget.modelPath;
    }

    // Check for user-uploaded labels from ModelProvider
    if (effectiveModelPath != null) {
      try {
        final modelProvider = Provider.of<ModelProvider>(
          context,
          listen: false,
        );
        final freshUserLabels = modelProvider.getLabelsForModelPath(
          effectiveModelPath,
        );

        if (freshUserLabels != null && freshUserLabels.isNotEmpty) {
          if (_userLabels != freshUserLabels) {
            _userLabels = freshUserLabels;
            return true;
          }
        } else if (_userLabels != null) {
          // User cleared labels
          _userLabels = null;
          return true;
        }
      } catch (e) {
        // ModelProvider not available in context
      }
    }
    return false;
  }

  /// PROCESSED FRAME HANDLER (Legacy / Fallback)
  /// Decode and display a frame with proper UI thread management and FPS calculation
  void _decodeAndDisplayFrame(ProcessedFrame frame) {
    if (!mounted || !_isActive) return;

    // Schedule frame decoding after current frame to avoid blocking during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActive) {
        return;
      }

      try {
        ui.decodeImageFromPixels(
          frame.imageBytes,
          frame.width,
          frame.height,
          ui.PixelFormat.rgba8888,
          (ui.Image image) {
            if (!mounted || !_isActive) {
              image.dispose();
              return;
            }

            // Calculate Stable FPS (Rolling Average)
            _statsTracker.onFrameDisplayed();
            _statsTracker.updateTiming(frame.timingBreakdown);

            // Update state with decoded image and FPS stats
            setState(() {
              _currentImage?.dispose();
              _currentImage = image;
              _currentDetections = frame.detections;
              _currentWidth = frame.width;
              _currentHeight = frame.height;
            });

            // Process pending frame if one arrived while we were decoding
            if (_pendingFrame != null) {
              final pending = _pendingFrame!;
              _pendingFrame = null;
              // Schedule next decode immediately on microtask to separate stack
              Future.microtask(() => _decodeAndDisplayFrame(pending));
            }
          },
        );
      } catch (e) {
        debugPrint("Error decoding frame: $e");
      }
    });
  }

  @override
  void didUpdateWidget(covariant DetachedStreamPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initialize();
  }

  @override
  void dispose() {
    _isActive = false;
    _frameSubscription?.cancel();
    _fpsTimer?.cancel();
    _currentImage?.dispose();
    _syncManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // 1. VIDEO LAYER
          if (_syncManager.textureId != null)
            // TEXTURE PATH (Zero-Copy)
            Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _currentWidth > 0
                      ? _currentWidth / _currentHeight
                      : 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Texture(textureId: _syncManager.textureId!),
                      // Detections Overlay
                      if (_currentDetections.isNotEmpty)
                        CustomPaint(
                          painter: DetectionOverlayPainter(
                            detections: _currentDetections,
                            originalSize: Size(
                              _currentWidth.toDouble(),
                              _currentHeight.toDouble(),
                            ),
                            customLabels: _userLabels ?? _modelLabels,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
          else if (_currentImage != null)
            // LEGACY PATH (Bitmap)
            Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _currentWidth / _currentHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // CORRECT RENDERING: Use RawImage with the decoded ui.Image
                      RawImage(image: _currentImage, fit: BoxFit.contain),
                      if (_currentDetections.isNotEmpty)
                        CustomPaint(
                          painter: DetectionOverlayPainter(
                            detections: _currentDetections,
                            originalSize: Size(
                              _currentWidth.toDouble(),
                              _currentHeight.toDouble(),
                            ),
                            customLabels: _userLabels ?? _modelLabels,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
          else if (_currentWidth > 0 && _currentDetections.isNotEmpty)
            // NO-VIDEO MODE: Just show overlays on black canvas
            Container(
              color: Colors.black,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _currentWidth / _currentHeight,
                  child: CustomPaint(
                    painter: DetectionOverlayPainter(
                      detections: _currentDetections,
                      originalSize: Size(
                        _currentWidth.toDouble(),
                        _currentHeight.toDouble(),
                      ),
                      customLabels: _userLabels ?? _modelLabels,
                    ),
                  ),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),

          // Overlay Info
          StatsOverlay(
            fps: _statsTracker.fps,
            decodeMs: _statsTracker.decodeMs,
            inferenceMs: _statsTracker.inferenceMs,
            postprocessMs: _statsTracker.postprocessMs,
          ),
        ],
      ),
    );
  }
}
