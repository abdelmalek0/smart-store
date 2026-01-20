import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';
import 'package:smart_store_linux/core/models/frames.dart';
import 'package:smart_store_linux/backend/services/texture_service.dart'; // GPU textures

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

  // Stats
  int _decodeMs = 0;
  int _inferenceMs = 0;
  int _postprocessMs = 0;
  Timer? _fpsTimer;
  StreamSubscription? _frameSubscription;

  // Frame rate limiting - prevent UI thread overload
  bool _isDecodingFrame = false;
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
      // Connect to Headless Processor
      final externalProcessor = StreamProcessManager.instance.getProcessor(
        widget.streamId,
      );

      if (externalProcessor != null && externalProcessor.isInitialized) {
        debugPrint("Attached to processor for ${widget.streamId}");

        // Create GPU texture for this stream (Linux platform texture)
        final textureService = TextureService();
        final textureResult = await textureService.createVideoTexture(
          _currentWidth,
          _currentHeight,
        );

        if (textureResult != null) {
          setState(() {
            _textureId = textureResult['textureId'];
            _textureManagerId = textureResult['textureManagerId'];
          });
          debugPrint(
            "[TEXTURE] Created texture $_textureId (manager: $_textureManagerId)",
          );

          // Connect stream to texture for automatic frame updates
          // Use ACTUAL Native Video ID (from Video_Open)
          final videoId = externalProcessor.nativeVideoId;
          if (videoId > 0) {
            await textureService.connectStreamToTexture(
              videoId,
              _textureManagerId!,
            );
            debugPrint("[TEXTURE] Connected video $videoId to texture");
          } else {
            debugPrint("[TEXTURE] Warning: Native Video ID not ready yet!");
          }
        } else {
          debugPrint("[TEXTURE] Failed to create texture, using CPU fallback");
        }

        // Listen to processed frames (for Detections & FPS stats)
        _frameSubscription = externalProcessor.frameStream.listen((frame) {
          if (!mounted || !_isActive) return;

          // TEXTURE MODE: Synchronized Display (Render-on-Demand)
          if (_textureId != null) {
            // Linux Texture Mode: Texture is updated natively by inference_bridge
            // We just need to trigger a repaint via updateTexture later

            // 2. Update UI Overlay immediately
            setState(() {
              _currentDetections = frame.detections;
              _currentWidth = frame.width;
              _currentHeight = frame.height;

              final timing = frame.timingBreakdown;
              _decodeMs = timing['decode'] ?? 0;
              _inferenceMs = timing['inference'] ?? 0;
              _postprocessMs = timing['postprocess'] ?? 0;

              // FPS Calculation (Based on display updates)
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

            // 3. Trigger texture repaint
            TextureService().updateTexture(_textureId!);
            return;
          }

          // LEGACY MODE: Image Decoding (Slow Path)
          // Skip if no video data (optimized detections-only path)
          if (frame.imageBytes.isEmpty) {
            setState(() {
              _currentDetections = frame.detections;
              _currentWidth = frame.width;
              _currentHeight = frame.height;

              final timing = frame.timingBreakdown;
              _decodeMs = timing['decode'] ?? 0;
              _inferenceMs = timing['inference'] ?? 0;
              _postprocessMs = timing['postprocess'] ?? 0;

              // FPS calculation
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

          // Frame rate limiting: If we're already decoding, save this as pending
          // This prevents the UI thread from being overwhelmed with decode requests
          if (_isDecodingFrame) {
            _pendingFrame = frame;
            return;
          }

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

    _isDecodingFrame = true;

    // Extract timing
    final timing = frame.timingBreakdown;

    final decodeStart = DateTime.now().millisecondsSinceEpoch;

    // Schedule frame decoding after current frame to avoid blocking during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActive) {
        _isDecodingFrame = false;
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
              _isDecodingFrame = false;
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

            _isDecodingFrame = false;

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
        _isDecodingFrame = false;
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
                    ),
                  ),
                ),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),

          // Overlay Info - LARGE FPS for Release Mode
          Positioned(
            top: 20,
            left: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display FPS (Big)
                Text(
                  "FPS: ${_fps.toStringAsFixed(1)}",
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        offset: Offset(2, 2),
                        blurRadius: 4,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
                // Pipeline Stats (Smaller)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_decodeMs > 0 || _inferenceMs > 0)
                        Text(
                          "D:${_decodeMs}ms I:${_inferenceMs}ms P:${_postprocessMs}ms",
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DetectionOverlayPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size originalSize;

  DetectionOverlayPainter({
    required this.detections,
    required this.originalSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    final Paint paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint textBgPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    const textStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );

    // Scale factors
    final double scaleX = size.width / originalSize.width;
    final double scaleY = size.height / originalSize.height;

    // Fit: BoxFit.contain logic
    // We need to match the scaling logic of Image.memory(fit: BoxFit.contain)
    // The image is centered and scaled to fit within 'size' while maintaining aspect ratio.

    double renderW = originalSize.width * scaleX;
    double renderH = originalSize.height * scaleY;

    // Actually, scaleX and scaleY are just ratios of container/original
    // But BoxFit.contain uses the smaller ratio for BOTH dimensions.
    double scale = 0.0;
    double offsetX = 0.0;
    double offsetY = 0.0;

    double aspectRatio = originalSize.width / originalSize.height;
    double containerRatio = size.width / size.height;

    if (containerRatio > aspectRatio) {
      // Container is wider than image. Image is height-constrained.
      scale = size.height / originalSize.height;
      offsetX = (size.width - (originalSize.width * scale)) / 2;
    } else {
      // Container is taller than image. Image is width-constrained.
      scale = size.width / originalSize.width;
      offsetY = (size.height - (originalSize.height * scale)) / 2;
    }

    for (var det in detections) {
      // Assuming detection format: [x1, y1, x2, y2, confidence, classId]
      // Coordinate system of detections is typically related to the INFERENCE INPUT size (640x640)
      // OR normalized?
      // If InferenceService returns raw YOLO output, it might be 0-640.
      // We need to map 640x640 -> originalSize -> renderSize.

      // Let's assume detections are normalized 0-1 or we know the input size (640).
      // If we don't know, we might have misaligned boxes.
      // Standard YOLO output from 'ort' usually needs post-processing to be usable [x,y,w,h].
      // Since InferenceService is generic returning 'List<dynamic>', I'll assume they are [x1, y1, x2, y2, ...]
      // relative to the 640x640 model input.

      if (det is List && det.length >= 4) {
        // Coordinates from C++ are already in original image space (e.g., 1280x720)
        // NOT in model space (320x320) - the C++ post_process already converted them
        double x1 = (det[0] as num).toDouble();
        double y1 = (det[1] as num).toDouble();
        double x2 = (det[2] as num).toDouble();
        double y2 = (det[3] as num).toDouble();

        // Transform from original image coords to screen coords
        // The image is displayed with BoxFit.contain, so we need to:
        // 1. Scale by the contain scale factor (same for both X and Y to maintain aspect ratio)
        // 2. Add the centering offset
        double screenX1 = (x1 * scale) + offsetX;
        double screenY1 = (y1 * scale) + offsetY;
        double screenX2 = (x2 * scale) + offsetX;
        double screenY2 = (y2 * scale) + offsetY;

        // Draw bounding box
        canvas.drawRect(
          Rect.fromLTRB(screenX1, screenY1, screenX2, screenY2),
          paint,
        );

        // Draw label with confidence
        if (det.length >= 5) {
          final double confidence = (det[4] as num).toDouble();
          final String label = 'object'; // Default label
          final String text =
              '${label} ${(confidence * 100).toStringAsFixed(1)}%';

          final textSpan = TextSpan(text: text, style: textStyle);
          final textPainter = TextPainter(
            text: textSpan,
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();

          // Draw background for text
          final textOffset = Offset(
            screenX1,
            screenY1 - textPainter.height - 4,
          );
          final textBgRect = Rect.fromLTWH(
            textOffset.dx,
            textOffset.dy,
            textPainter.width + 8,
            textPainter.height + 4,
          );
          canvas.drawRect(textBgRect, textBgPaint);

          // Draw text
          textPainter.paint(canvas, textOffset.translate(4, 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.originalSize != originalSize;
  }
}
