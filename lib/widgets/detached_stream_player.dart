import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:bitmap/bitmap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart';
import 'package:image/image.dart' as img;
import 'package:smart_store_linux/services/inference_service.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

class DetachedStreamPlayer extends StatefulWidget {
  final String url;
  final String? modelPath;
  final String? label;

  const DetachedStreamPlayer({
    super.key,
    required this.url,
    this.modelPath,
    this.label,
  });

  @override
  State<DetachedStreamPlayer> createState() => _DetachedStreamPlayerState();
}

class _DetachedStreamPlayerState extends State<DetachedStreamPlayer> {
  VideoPlayerController? _controller;
  bool _isActive = true;

  // Queues
  final Queue<Uint8List> _rawFrameQueue = Queue<Uint8List>();
  final Queue<_DisplayFrame> _displayQueue = Queue<_DisplayFrame>();
  final int _queueLimit = 3; // Tight loop for realtime

  // Display
  _DisplayFrame? _currentFrame;
  List<dynamic> _lastDetections = []; // Persist detections across frames

  // Stats
  int _fps = 0;
  int _displayedFrameCount = 0; // Track actually displayed frames
  int _inferenceFrameCounter = 0; // For frame skipping
  Timer? _fpsTimer;
  DateTime? _lastFpsUpdate;

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
    try {
      debugPrint("Initializing video for: ${widget.url}");
      
      // Initialize inference service and load model if provided
      if (widget.modelPath != null) {
        debugPrint("Loading model: ${widget.modelPath}");
        await InferenceService().init();
        final loaded = await InferenceService().loadModel(widget.modelPath!);
        if (loaded) {
          debugPrint("Model loaded successfully: ${widget.modelPath}");
        } else {
          debugPrint("Failed to load model: ${widget.modelPath}");
        }
      }
      
      final VideoPlayerOptions videoPlayerOptions = VideoPlayerOptions(mixWithOthers: true);

      if (widget.url.startsWith('http') || widget.url.startsWith('rtsp')) {
        debugPrint("Initializing network stream: ${widget.url}");
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.url),
          videoPlayerOptions: videoPlayerOptions,
        );
      } else {
        // Local file - validate it exists
        final file = File(widget.url);
        if (!await file.exists()) {
          debugPrint("ERROR: File does not exist: ${widget.url}");
          if (mounted) {
            setState(() {});
          }
          return;
        }
        
        final fileSize = await file.length();
        debugPrint("Initializing local file: ${widget.url} (${fileSize} bytes)");
        
        // Try to get absolute path
        final absolutePath = file.absolute.path;
        debugPrint("Absolute path: $absolutePath");
        
        _controller = VideoPlayerController.file(
          File(absolutePath),
          videoPlayerOptions: videoPlayerOptions,
        );
      }

      debugPrint("Calling controller.initialize()...");
      await _controller!.initialize();
      debugPrint("Controller initialized. Size: ${_controller!.value.size}");
      
      await _controller!.setLooping(true);
      await _controller!.setVolume(0);
      
      // Add listener to debug state
      _controller!.addListener(() {
        if (_controller!.value.hasError) {
          debugPrint("Video Error: ${_controller!.value.errorDescription}");
        }
      });

      debugPrint("Starting playback...");
      await _controller!.play();
      
      // Retry strategy if not playing
      if (!_controller!.value.isPlaying) {
         debugPrint("Video not playing immediately. Retrying...");
         await Future.delayed(const Duration(milliseconds: 500));
         await _controller!.play();
      }
      
      debugPrint("Video initialized. Playing: ${_controller!.value.isPlaying} Size: ${_controller!.value.size}");

      // Check for error immediately
      if (_controller!.value.hasError) {
         debugPrint("Controller has error: ${_controller!.value.errorDescription}");
         return;
      }

      // Start the decoupled loops
      _startReadLoop();
      _startInferenceLoop();
      _startDisplayLoop();
    } catch (e, stack) {
      debugPrint("Error initializing video: $e\n$stack");
      if (mounted) {
        setState(() {});
      }
    }
  }

  // --- LOOP 1: READ ---
  void _startReadLoop() async {
    // Give the player time to warm up and stabilize texture
    debugPrint("Read loop waiting for warmup...");
    await Future.delayed(const Duration(seconds: 3));
    debugPrint("Read loop started");

    while (_isActive && mounted) {
      if (_controller != null && _controller!.value.isPlaying) {
        try {
          // debugPrint("Requesting snapshot...");
          // FVP snapshot
          try {
            final Uint8List? frameBytes = await _controller!.snapshot()
                .timeout(const Duration(milliseconds: 1000));
            
            if (frameBytes != null) {
              // debugPrint("Snapshot success: ${frameBytes.length} bytes");
              if (_rawFrameQueue.length >= _queueLimit) {
                _rawFrameQueue.removeFirst();
              }
              _rawFrameQueue.add(frameBytes);
              // debugPrint("Raw Q size: ${_rawFrameQueue.length}");
            } else {
               // debugPrint("Snapshot returned null");
            }
          } on TimeoutException {
             debugPrint("Snapshot timed out - player might be stalled");
          } catch (e) {
            debugPrint("Read loop snapshot error: $e");
          }
        } catch (e) {
          debugPrint("Read loop outer error: $e");
        }
      } else {
        // debugPrint("Controller status: ${_controller?.value.isPlaying}");
      }
      // Poll interval - 25 FPS approx
      await Future.delayed(const Duration(milliseconds: 40)); 
    }
  }

  // --- LOOP 2: INFERENCE & PROCESS ---
  void _startInferenceLoop() async {
    debugPrint("Inference loop started");
    while (_isActive && mounted) {
      if (_rawFrameQueue.isNotEmpty) {
        final Uint8List rawBytes = _rawFrameQueue.removeFirst();
        
        if (_controller == null || !_controller!.value.isInitialized) {
             continue;
        }
        final int w = _controller!.value.size.width.toInt();
        final int h = _controller!.value.size.height.toInt();
        
        // Verify size matches bytes
        if (rawBytes.length != w * h * 4) {
           debugPrint("Mismatch: Bytes=${rawBytes.length} vs Expected=${w*h*4}");
           continue;
        }

        // Construct directly
        final img.Image decoded = img.Image.fromBytes(
            width: w, 
            height: h, 
            bytes: rawBytes.buffer,
            numChannels: 4 
        );
        
        if (decoded != null) {
          List<dynamic> detections = _lastDetections; // Start with last known detections
          bool shouldDisplay = true;

          // 2. Inference (if model present)
          if (widget.modelPath != null) {
            // Run inference only every 3rd frame to improve FPS
            _inferenceFrameCounter++;
            if (_inferenceFrameCounter % 3 == 0) {
              // Resize in isolate for better performance
              try {
                final resizedBytes = await compute(_resizeImageForInference, {
                  'bytes': rawBytes,
                  'width': w,
                  'height': h,
                });
                
                detections = await InferenceService().runInference(
                  widget.modelPath!, 
                  resizedBytes, 
                  [1, 640, 640, 3]
                );
                _lastDetections = detections;
                
                if (detections.isNotEmpty) {
                  debugPrint("Frame Detections: ${detections.length}");
                }
              } catch (e) {
                debugPrint("Inference error in loop: $e");
              }
            }
          }

          if (shouldDisplay) {
            // 3. Prepare for Display (Bitmap) - optimize by avoiding repeated buildHeaded() calls
            final displayFrame = _DisplayFrame(
              rawBytes, // Store raw bytes instead of bitmap
              w,
              h,
              detections,
            );

            if (_displayQueue.length >= _queueLimit) {
              _displayQueue.removeFirst();
            }
            _displayQueue.add(displayFrame);
          }
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  // Static function to resize image in isolate
  static Uint8List _resizeImageForInference(Map<String, dynamic> params) {
    final Uint8List bytes = params['bytes'] as Uint8List;
    final int width = params['width'] as int;
    final int height = params['height'] as int;
    
    final img.Image decoded = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      numChannels: 4,
    );
    
    final resized = img.copyResize(decoded, width: 640, height: 640);
    return resized.getBytes();
  }

  Future<void> _runInference(img.Image image, String modelPath) async {
    // Resize for model if needed (e.g. 640x640)
    // For efficiency we might want to resize ONCE for both display and inference if they match,
    // or keep high res for display and low for inference.
    // For this implementation: Resize for inference, but display original (or close to it)
    // Actually, to display the inference results (bounding boxes), we usually draw on the same image.
    // So let's resize to 640x640 for consistency if that's the model expectation.
    
    // final resized = img.copyResize(image, width: 640, height: 640);
    // final bytes = resized.getBytes();
    
    // In InferenceService, it expects bytes and shape.
    // We already have generic 'runInference'.
    
    // await InferenceService().runInference(modelPath, bytes, [1, 640, 640, 3]);
    
    // Note: To avoid blocking the UI thread with too much work, we rely on the fact this loop is async 
    // but Dart is single threaded event loop. 
    // Ideally, heavy image processing should be in an Isolate.
    // Given the constraints and the "detached pipeline" request running in main isolate (via async),
    // we proceed.
  }

  // --- LOOP 3: DISPLAY ---
  void _startDisplayLoop() async {
    while (_isActive && mounted) {
      if (_displayQueue.isNotEmpty) {
        final _DisplayFrame frame = _displayQueue.removeFirst();
        setState(() {
          _currentFrame = frame;
          _displayedFrameCount++; // Count actually displayed frames
        });
      }
      // Target 30-60 FPS refresh
      await Future.delayed(const Duration(milliseconds: 16));
    }
  }

  @override
  void dispose() {
    _isActive = false;
    _fpsTimer?.cancel();
    _controller?.dispose();
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
        fit: StackFit.passthrough, // Changed from expand to preserve aspect ratio
        children: [
          // 1. Native Video Player (ALWAYS present for snapshots, but covered by processed frames)
          // Must remain visible and on-screen for FVP snapshot() to work
          if (_controller != null && _controller!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),

          if (_controller == null || !_controller!.value.isInitialized)
             const Center(
               child: CircularProgressIndicator(color: AppTheme.accent),
             ),

          // 2. Overlay Layer: Processed/Inference Frame (covers VideoPlayer when present)
          if (_currentFrame != null)
            Container(
              color: Colors.black, // Ensure it covers the VideoPlayer completely
              child: Center(
                child: AspectRatio(
                  aspectRatio: _currentFrame!.bitmap.width / _currentFrame!.bitmap.height,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // Bitmap - build only once per frame
                          Image.memory(
                            _currentFrame!.bitmap.buildHeaded(),
                            gaplessPlayback: true,
                            fit: BoxFit.contain,
                          ),
                          // Detections Overlay
                          if (_currentFrame!.detections.isNotEmpty)
                            CustomPaint(
                              painter: DetectionOverlayPainter(
                                detections: _currentFrame!.detections,
                                originalSize: Size(
                                   _currentFrame!.bitmap.width.toDouble(),
                                   _currentFrame!.bitmap.height.toDouble(),
                                ),
                              ),
                            ),
                        ],
                      );
                    }
                  ),
                ),
              ),
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
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  Text(
                    "FPS: $_fps | Q: ${_rawFrameQueue.length}/${_displayQueue.length}",
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'monospace'),
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

class _DisplayFrame {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final List<dynamic> detections;
  Bitmap? _cachedBitmap; // Cache bitmap to avoid rebuilding

  _DisplayFrame(this.imageBytes, this.width, this.height, this.detections);
  
  Bitmap get bitmap {
    _cachedBitmap ??= Bitmap.fromHeadless(width, height, imageBytes);
    return _cachedBitmap!;
  }
}

class DetectionOverlayPainter extends CustomPainter {
  final List<dynamic> detections;
  final Size originalSize;

  DetectionOverlayPainter({required this.detections, required this.originalSize});

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
          canvas.drawRect(Rect.fromLTRB(screenX1, screenY1, screenX2, screenY2), paint);
          
          // Draw label with confidence
          if (det.length >= 5) {
            final double confidence = (det[4] as num).toDouble();
            final String label = 'object'; // Default label
            final String text = '${label} ${(confidence * 100).toStringAsFixed(1)}%';
            
            final textSpan = TextSpan(
              text: text,
              style: textStyle,
            );
            final textPainter = TextPainter(
              text: textSpan,
              textDirection: TextDirection.ltr,
            );
            textPainter.layout();
            
            // Draw background for text
            final textOffset = Offset(screenX1, screenY1 - textPainter.height - 4);
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
