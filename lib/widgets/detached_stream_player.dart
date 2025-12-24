import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/services/stream_process_manager.dart';
import 'package:smart_store_linux/models/frames.dart';

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

  // Display state - no internal queue, processor manages queues
  ui.Image? _currentImage;
  List<dynamic> _currentDetections = [];
  int _currentWidth = 0;
  int _currentHeight = 0;

  // Stats
  int _fps = 0;
  int _displayedFrameCount = 0;
  Timer? _fpsTimer;
  StreamSubscription? _frameSubscription;

  // Frame rate limiting - prevent UI thread overload
  bool _isDecodingFrame = false;
  ProcessedFrame? _pendingFrame;

  @override
  void initState() {
    super.initState();
    _initialize();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _fps = _displayedFrameCount;
          _displayedFrameCount = 0;
        });
      }
    });
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

        // Listen to processed frames from processor's DisplayQueue
        _frameSubscription = externalProcessor.frameStream.listen((frame) {
          if (!mounted || !_isActive) return;

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

  /// Decode and display a frame with proper UI thread management
  void _decodeAndDisplayFrame(ProcessedFrame frame) {
    if (!mounted || !_isActive) return;

    _isDecodingFrame = true;

    // Schedule frame decoding after current frame to avoid blocking during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActive) {
        _isDecodingFrame = false;
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
              _isDecodingFrame = false;
              return;
            }

            // Update state with decoded image
            setState(() {
              _currentImage?.dispose();
              _currentImage = image;
              _currentDetections = frame.detections;
              _currentWidth = frame.width;
              _currentHeight = frame.height;
              _displayedFrameCount++;
            });

            _isDecodingFrame = false;

            // Process pending frame if one arrived while we were decoding
            if (_pendingFrame != null) {
              final pending = _pendingFrame!;
              _pendingFrame = null;
              _decodeAndDisplayFrame(pending);
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
          // 1. Image Layer (from Native Capture)
          if (_currentImage != null)
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
            ),

          if (_currentImage == null)
            const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),

          // Overlay Info
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.label != null)
                    Text(
                      widget.label!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  Text(
                    "FPS: $_fps",
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (widget.modelPath != null)
                    const Text(
                      "AI: ON",
                      style: TextStyle(color: Colors.blueAccent, fontSize: 10),
                    ),
                ],
              ),
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
        double x1 = (det[0] as num).toDouble();
        double y1 = (det[1] as num).toDouble();
        double x2 = (det[2] as num).toDouble();
        double y2 = (det[3] as num).toDouble();

        // Transform 640x640 -> Original
        // The inference input was resized from Original.
        // So x / 640 = originalX / originalW

        double origX1 = x1 / 640 * originalSize.width;
        double origY1 = y1 / 640 * originalSize.height;
        double origX2 = x2 / 640 * originalSize.width;
        double origY2 = y2 / 640 * originalSize.height;

        // Transform Original -> Render (Screen)
        double screenX1 = (origX1 * scale) + offsetX;
        double screenY1 = (origY1 * scale) + offsetY;
        double screenX2 = (origX2 * scale) + offsetX;
        double screenY2 = (origY2 * scale) + offsetY;

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
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
