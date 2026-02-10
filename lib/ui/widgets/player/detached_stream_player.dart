import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/backend/services/texture_service.dart'; // GPU textures
import 'package:smart_store_linux/backend/services/config_service.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/widgets/player/detection_overlay_painter.dart';
import 'package:smart_store_linux/ui/widgets/player/stats_overlay.dart';

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

  // Display state
  int? _textureId; // Flutter texture ID for rendering
  int? _textureManagerId; // Native TextureManager ID
  ui.Image? _currentImage;
  List<dynamic> _currentDetections = [];
  int _currentWidth = 1920; // Default to full HD
  int _currentHeight = 1080;

  // Model labels from ONNX metadata (received from StreamProcessor)
  Map<int, String> _modelLabels = {};

  // User-uploaded custom labels (takes priority over _modelLabels)
  Map<int, String>? _userLabels;

  // Stats
  int _decodeMs = 0;
  int _inferenceMs = 0;
  int _postprocessMs = 0;
  Timer? _fpsTimer;
  StreamSubscription? _frameSubscription;

  // Frame rate limiting - prevent UI thread overload
  ProcessedFrame? _pendingFrame;

  // Track frames for averaging FPS
  // Stabilized FPS - Rolling Window (last 30 frames)
  final List<int> _frameTimestamps = [];
  static const int FPS_WINDOW_SIZE = 30;
  double _fps = 0.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_frameSubscription != null) return; // Already listening

    try {
      final externalProcessor = StreamProcessManager.instance.getProcessor(
        widget.streamId,
      );

      // Stream ID should be valid if we are here
      if (externalProcessor != null) {
        debugPrint("Attached to processor for ${widget.streamId}");

        // 1. Initial State Sync
        // Apply existing state if processor is already running
        if (mounted) {
          // Get model path using same resolution logic as StreamProcessor:
          // 1. Stream-specific plugin config
          // 2. Global plugin config
          // 3. Widget fallback
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

          debugPrint(
            "[LABELS] Stream: ${widget.streamId}, EffectiveModelPath: $effectiveModelPath",
          );

          // Check for user-uploaded labels from ModelProvider
          if (effectiveModelPath != null) {
            try {
              final modelProvider = Provider.of<ModelProvider>(
                context,
                listen: false,
              );
              _userLabels = modelProvider.getLabelsForModelPath(
                effectiveModelPath,
              );
              debugPrint(
                "[LABELS] Found user labels: ${_userLabels?.length ?? 0} entries",
              );
            } catch (e) {
              debugPrint("[LABELS] Error getting ModelProvider: $e");
            }
          } else {
            debugPrint("[LABELS] No modelPath available for labels");
          }

          setState(() {
            if (externalProcessor.frameWidth > 0) {
              _currentWidth = externalProcessor.frameWidth;
            }
            if (externalProcessor.frameHeight > 0) {
              _currentHeight = externalProcessor.frameHeight;
            }
            // Only use native labels if no user labels
            if (_userLabels == null &&
                externalProcessor.modelLabels.isNotEmpty) {
              _modelLabels = externalProcessor.modelLabels;
            }
            // For Android, check if texture ID is already available
            if (Platform.isAndroid && externalProcessor.textureId != null) {
              _textureId = externalProcessor.textureId;
            }
          });
        }

        // 2. Linux Texture Creation (Platform Specific)
        // Android uses native texture from plugin. Linux needs explicit creation.
        bool isLinuxTextureConnected = false;

        if (Platform.isLinux) {
          try {
            // Create texture surface
            final textureService = TextureService();
            final textureResult = await textureService.createVideoTexture(
              _currentWidth,
              _currentHeight,
            );

            if (textureResult != null && mounted) {
              setState(() {
                _textureId = textureResult['textureId'];
                _textureManagerId = textureResult['textureManagerId'];
              });
              // debugPrint("[TEXTURE] Created Linux Texture $_textureId");
            }
          } catch (e) {
            debugPrint("[TEXTURE] Linux creation error: $e");
          }
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

          // Android: Pick up texture ID if it arrives late
          if (Platform.isAndroid &&
              _textureId == null &&
              externalProcessor.textureId != null) {
            _textureId = externalProcessor.textureId;
            needsSetState = true;
          }

          // Linux: Connect stream to texture when Video ID becomes available
          if (Platform.isLinux &&
              !isLinuxTextureConnected &&
              _textureManagerId != null &&
              externalProcessor.nativeVideoId > 0) {
            try {
              await TextureService().connectStreamToTexture(
                externalProcessor.nativeVideoId,
                _textureManagerId!,
              );
              isLinuxTextureConnected = true;
              debugPrint("[TEXTURE] Connected Linux stream to texture");
            } catch (e) {
              // Ignore temporary connection errors
            }
          }

          // Labels Sync - Check for user labels update from ModelProvider
          String? syncModelPath = ConfigService.instance.getModelForStream(
            widget.streamId,
          );
          if (syncModelPath == null) {
            final pluginId =
                ConfigService.instance.getStreamActivePlugin(widget.streamId) ??
                'people_counting';
            final globalConfig = ConfigService.instance.getGlobalPluginConfig(
              pluginId,
            );
            syncModelPath =
                globalConfig?['modelPath'] as String? ?? widget.modelPath;
          }
          if (syncModelPath != null && mounted) {
            try {
              final modelProvider = Provider.of<ModelProvider>(
                context,
                listen: false,
              );
              final freshUserLabels = modelProvider.getLabelsForModelPath(
                syncModelPath,
              );
              if (freshUserLabels != null && freshUserLabels.isNotEmpty) {
                if (_userLabels != freshUserLabels) {
                  _userLabels = freshUserLabels;
                  needsSetState = true;
                }
              } else if (_userLabels != null) {
                // User cleared labels
                _userLabels = null;
                needsSetState = true;
              }
            } catch (e) {
              // ModelProvider not available in context
            }
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

          // B. Android Render Trigger
          // Android requires explicit 'showFrame' to update the SurfaceTexture
          // STRICT SYNC: If native buffer doesn't have the frame, we MUST skipping updating UI.
          // This keeps the overlay synchronized with the "stuck" video frame.
          if (Platform.isAndroid && _textureId != null) {
            final success = await externalProcessor.showFrame(
              frame.decodeStartMs,
            );
            if (!success) {
              // Frame dropped/missing in native buffer.
              // Do NOT update overlays, or they will drift ahead of the stuck video.
              return;
            }
          }

          // C. Texture Update / Repaint
          if (Platform.isLinux &&
              _textureManagerId != null &&
              _textureId != null) {
            TextureService().updateTexture(_textureId!);
          }

          // D. Update UI Data (FPS, Detections) - Optimized Path
          // Use Optimized Path if we are in Texture Mode (ignoring redundant bytes)
          // OR if we have no bytes (inference only)
          if (_textureId != null || frame.imageBytes.isEmpty) {
            setState(() {
              _currentDetections = frame.detections;
              _currentWidth = frame.width;
              _currentHeight = frame.height;

              // FPS Calc
              final now = DateTime.now().millisecondsSinceEpoch;
              _frameTimestamps.add(now);
              if (_frameTimestamps.length > FPS_WINDOW_SIZE) {
                _frameTimestamps.removeAt(0);
              }
              if (_frameTimestamps.length >= 2) {
                final duration = _frameTimestamps.last - _frameTimestamps.first;
                if (duration > 0) {
                  _fps = ((_frameTimestamps.length - 1) * 1000) / duration;
                }
              }
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

  /// PROCESSED FRAME HANDLER (Legacy / Fallback)
  /// Decode and display a frame with proper UI thread management and FPS calculation
  void _decodeAndDisplayFrame(ProcessedFrame frame) {
    if (!mounted || !_isActive) return;

    // Extract timing
    final timing = frame.timingBreakdown;

    final decodeStart = DateTime.now().millisecondsSinceEpoch;

    // Schedule frame decoding after current frame to avoid blocking during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActive) {
        return;
      }

      try {
        // Verify resolution (Native changes require full rebuild)
        if (_frameTimestamps.length % 60 == 0) {
          debugPrint("Frame Size: ${frame.width}x${frame.height}");
        }

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

            final decodeDuration =
                DateTime.now().millisecondsSinceEpoch - decodeStart;
            // Only log if slow (> 30ms) to avoid flood
            if (decodeDuration > 30) {
              debugPrint("⚠️ UI Decode Slow: ${decodeDuration}ms");
            }

            // Calculate Stable FPS (Rolling Average)
            final now = DateTime.now().millisecondsSinceEpoch;
            _frameTimestamps.add(now);

            // Keep only the last N timestamps
            if (_frameTimestamps.length > FPS_WINDOW_SIZE) {
              _frameTimestamps.removeAt(0); // Remove oldest
            }

            // Calculate FPS over the whole window
            if (_frameTimestamps.length >= 2) {
              final durationMs = _frameTimestamps.last - _frameTimestamps.first;
              if (durationMs > 0) {
                // FPS = (Frames - 1) / DurationSeconds
                // Frames including the first one, but intervals are (Frames - 1)
                _fps = ((_frameTimestamps.length - 1) * 1000) / durationMs;
              }
            }

            // Update state with decoded image and FPS stats
            setState(() {
              _currentImage?.dispose();
              _currentImage = image;
              _currentDetections = frame.detections;
              _currentWidth = frame.width;
              _currentHeight = frame.height;

              // Update timing breakdown
              _decodeMs = timing['decode'] ?? 0;
              _inferenceMs = timing['inference'] ?? 0;
              _postprocessMs = timing['postprocess'] ?? 0;
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
          if (_textureId != null)
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
                      Texture(textureId: _textureId!),
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
            fps: _fps,
            decodeMs: _decodeMs,
            inferenceMs: _inferenceMs,
            postprocessMs: _postprocessMs,
          ),
        ],
      ),
    );
  }
}
