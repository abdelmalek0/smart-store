import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:smart_store_linux/ai/utils/constants.dart';
import 'package:smart_store_linux/ai/utils/yolo_processor.dart';
import 'package:smart_store_linux/ai/worker/messages.dart';
import 'package:smart_store_linux/ai/backend/inference_backend.dart';
import 'package:smart_store_linux/ai/backend/linux/onnx_backend.dart';
import 'package:smart_store_linux/ai/backend/android/rknn_backend.dart';

// ============================================================================
// WORKER ISOLATE - Handles inference in background
// ============================================================================

/// Worker isolate entry point
void inferenceWorkerEntry(WorkerInit init) {
  debugPrint("Worker Isolate Entry: Starting...");
  debugPrint("Worker: Started");
  final worker = InferenceWorker(init.sendPort);
  worker.run();
}

/// Inference worker that runs in a separate isolate
///
/// Responsibilities:
/// - Managing inference sessions via InquiryBackend
/// - Batching inference requests
/// - Running inference on available hardware (GPU/NPU)
/// - Post-processing YOLO outputs
class InferenceWorker {
  final SendPort mainSendPort;
  final ReceivePort _workerReceivePort = ReceivePort();

  late InferenceBackend _backend;
  // Map modelPath -> modelId (int)
  final Map<String, int> _loadedModels = {};

  final Queue<WorkerRequest> _requestQueue = Queue<WorkerRequest>();

  // ========================================
  // Configuration Constants - Optimized for Low Latency
  // ========================================
  // Using centralized Constants for consistency
  static const int MAX_BATCH_SIZE = AiConstants.maxBatchSize;
  static const int BATCH_WINDOW_MS = AiConstants.inferenceBatchIntervalMs;
  static const int QUEUE_SEARCH_LIMIT = 10; // Max items to search in queue
  static const int QUEUE_POLL_MS = 0; // Immediate polling for minimal latency

  InferenceWorker(this.mainSendPort);

  /// Run the worker - initialize and start processing
  void run() async {
    // 1. Send Port IMMEDIATELY
    mainSendPort.send(_workerReceivePort.sendPort);

    // 2. Select Backend
    if (Platform.isAndroid) {
      _backend = RknnInferenceBackend();
      debugPrint("Worker: Selected RKNN Backend");
    } else {
      _backend = OnnxInferenceBackend();
      debugPrint("Worker: Selected ONNX Backend");
    }

    try {
      await _backend.init();
      debugPrint("Worker: Backend initialized");
      mainSendPort.send(WorkerReady(true));
    } catch (e) {
      debugPrint("Worker: Init Failed: $e");
      mainSendPort.send(WorkerReady(false, e.toString()));
      return;
    }

    _workerReceivePort.listen((message) {
      if (message is WorkerRequest) {
        _requestQueue.add(message);
      }
    });

    _startBatchLoop();
  }

  /// Start the batch processing loop
  void _startBatchLoop() async {
    debugPrint("🚀 Inference worker started");
    while (true) {
      // Wait for requests
      if (_requestQueue.isEmpty) {
        await Future.delayed(Duration(milliseconds: QUEUE_POLL_MS));
        continue;
      }

      // ========================================
      // Initialize Batch
      // ========================================
      final firstReq = _requestQueue.removeFirst();
      final List<WorkerRequest> batch = [firstReq];
      final Set<String> batchStreamIds = {firstReq.streamId};

      final stopwatch = Stopwatch()..start();

      // ========================================
      // Collect Additional Batch Items
      // ========================================
      // Collect more items for the same model, but one per stream
      while (stopwatch.elapsedMilliseconds < BATCH_WINDOW_MS &&
          batch.length < MAX_BATCH_SIZE) {
        if (_requestQueue.isNotEmpty) {
          final List<WorkerRequest> skipped = [];
          int searched = 0;

          while (_requestQueue.isNotEmpty &&
              searched < QUEUE_SEARCH_LIMIT &&
              batch.length < MAX_BATCH_SIZE) {
            final req = _requestQueue.removeFirst();
            searched++;

            if (req.modelPath == firstReq.modelPath &&
                !batchStreamIds.contains(req.streamId)) {
              batch.add(req);
              batchStreamIds.add(req.streamId);
            } else {
              skipped.add(req);
            }
          }

          // Restore skipped
          for (var r in skipped.reversed) {
            _requestQueue.addFirst(r);
          }

          if (batch.length == MAX_BATCH_SIZE) break;
        }

        await Future.delayed(const Duration(milliseconds: 1));
      }

      // Process batch (no verbose logging)
      await _processBatch(batch);
    }
  }

  /// Process a batch of inference requests
  Future<void> _processBatch(List<WorkerRequest> batch) async {
    final modelPath = batch.first.modelPath;

    // Capture when processing actually starts (excludes queue wait time)
    final processingStartMs = DateTime.now().millisecondsSinceEpoch;

    final totalStopwatch = Stopwatch()..start();
    final inferenceStopwatch = Stopwatch();
    final postprocessStopwatch = Stopwatch();

    try {
      // ========================================
      // Load Model Session
      // ========================================
      var modelId = _loadedModels[modelPath];

      if (modelId == null) {
        try {
          debugPrint("📥 Loading model: ${modelPath.split('/').last}");
          final loadStart = Stopwatch()..start();

          modelId = await _backend.loadModel(modelPath, ModelType.yolo);
          _loadedModels[modelPath] = modelId;

          debugPrint(
            "✓ Model loaded in ${loadStart.elapsedMilliseconds}ms (ID: $modelId)",
          );
        } catch (e) {
          debugPrint("❌ Model load error: $e");
          _failBatch(batch, "Failed to load model: $e");
          return;
        }
      }

      // ========================================
      // Run Inference
      // ========================================
      inferenceStopwatch.start();

      final inputs = batch
          .map(
            (req) => InferenceInput(
              imageBytes: Uint8List.fromList(req.imageBytes),
              width: req.width,
              height: req.height,
              streamId: req.streamId,
            ),
          )
          .toList();

      final results = await _backend.run(modelId, inputs);

      inferenceStopwatch.stop();
      final inferenceMs = inferenceStopwatch.elapsedMilliseconds;

      if (results.length != batch.length) {
        _failBatch(
          batch,
          "Result count mismatch: ${results.length} vs ${batch.length}",
        );
        return;
      }

      // ========================================
      // Post Process
      // ========================================
      postprocessStopwatch.start();

      for (int i = 0; i < batch.length; i++) {
        final result = results[i];
        if (result.outputs.isEmpty) {
          _failBatch([batch[i]], "Empty inference result");
          continue;
        }

        final req = batch[i];

        try {
          List<List<double>> detections = [];

          if (result.metadata['format'] == 'detections_f32_6') {
            // Native C++ Processed Detections
            final bytes = result.outputs[0] as List<int>;
            final floats = Float32List.view(Uint8List.fromList(bytes).buffer);
            // Format: [Class, Score, Left, Top, Right, Bottom]
            for (int i = 0; i < floats.length; i += 6) {
              detections.add([
                floats[i + 2], // x1
                floats[i + 3], // y1
                floats[i + 4], // x2
                floats[i + 5], // y2
                floats[i + 1], // score
                floats[i + 0], // class
              ]);
            }
          } else if (Platform.isAndroid &&
              result.outputs.isNotEmpty &&
              result.outputs[0] is List<int>) {
            // RKNN specialized post-processing (Legacy / Fallback)
            // We need to cast back to expected types
            final outputs = result.outputs.map((e) => e.cast<int>()).toList();
            final attrs = result.metadata['attrs'] as List<dynamic>? ?? [];
            if (attrs.isNotEmpty) {
              detections = _postProcessYoloInt8(
                outputs,
                attrs,
                req.width,
                req.height,
              );
            } else {
              debugPrint("Missing attributes for RKNN post-processing");
            }
          } else if (result.outputs.isNotEmpty &&
              result.outputs[0] is List<double>) {
            // ONNX / Float post-processing using shared YoloProcessor
            final data = result.outputs[0].cast<double>();
            final yoloDetections = YoloPostProcessor.postProcessYoloFloat(
              data: data,
              originalWidth: req.width,
              originalHeight: req.height,
            );
            // Convert Detection objects to legacy list format [x1, y1, x2, y2, score, class]
            detections = yoloDetections.map((det) {
              return [
                det.x - det.width / 2, // x1
                det.y - det.height / 2, // y1
                det.x + det.width / 2, // x2
                det.y + det.height / 2, // y2
                det.confidence,
                det.classId.toDouble(),
              ];
            }).toList();
          }

          mainSendPort.send(
            WorkerResponse(
              streamId: req.streamId,
              requestId: req.requestId,
              modelPath: req.modelPath,
              detections: detections,
              processingStartMs: processingStartMs,
            ),
          );
        } catch (e) {
          debugPrint("Postprocess Error: $e");
          _failBatch([req], "Postprocess: $e");
        }
      }

      postprocessStopwatch.stop();
      totalStopwatch.stop();

      debugPrint(
        "⏱️ Batch[${batch.length}] timing: "
        "Inference=${inferenceMs}ms | "
        "Postprocess=${postprocessStopwatch.elapsedMilliseconds}ms | "
        "Total=${totalStopwatch.elapsedMilliseconds}ms",
      );
    } catch (e, st) {
      debugPrint("Worker Batch Error: $e\n$st");
      _failBatch(batch, e.toString());
    }
  }

  /// Fail a batch of requests
  void _failBatch(List<WorkerRequest> batch, String error) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var req in batch) {
      mainSendPort.send(
        WorkerResponse(
          streamId: req.streamId,
          requestId: req.requestId,
          modelPath: req.modelPath,
          detections: [],
          error: error,
          processingStartMs: now,
        ),
      );
    }
  }

  /// Post-process YOLO output - Int8 Quantized with 3 heads
  /// Handles standard YOLOv5/v7 anchors and strides (8, 16, 32)
  /// Converts coordinates from model space (640x640) to original image space
  List<List<double>> _postProcessYoloInt8(
    List<List<int>> outputs,
    List<dynamic> attrs,
    int originalWidth,
    int originalHeight,
  ) {
    if (outputs.length != 3 || attrs.length != 3) {
      debugPrint("⚠️ Unexpected output count: ${outputs.length}");
      return [];
    }

    final candidates = <List<double>>[];
    const anchors = [
      [10, 13, 16, 30, 33, 23], // Stride 8 (P3)
      [30, 61, 62, 45, 59, 119], // Stride 16 (P4)
      [116, 90, 156, 198, 373, 326], // Stride 32 (P5)
    ];

    // Assuming input 640x640
    const inputSize = 640;
    const confThresh = 0.5;

    for (int i = 0; i < 3; i++) {
      final data = outputs[i];
      final zp = attrs[i].zp;
      final scale = attrs[i].scale;
      final stride = 8 << i; // 8, 16, 32
      final gridSize = inputSize ~/ stride;
      final gridLen = gridSize * gridSize;
      final anchorList = anchors[i];

      // Threshold in int8 to avoid dequantizing everything
      // Val >= (thresh / scale) + zp
      final threshInt8 = (confThresh / scale) + zp;

      for (int a = 0; a < 3; a++) {
        for (int y = 0; y < gridSize; y++) {
          for (int x = 0; x < gridSize; x++) {
            // Check box confidence (index 4)
            // Channel offset = (a * 85) + 4
            // Index = channel_offset * gridLen + y * gridSize + x
            final pixelIdx = y * gridSize + x;
            final confChIdx = (a * 85) + 4;
            final confIdx = confChIdx * gridLen + pixelIdx;

            if (confIdx >= data.length) continue; // Safety

            final boxConfRaw = data[confIdx];
            if (boxConfRaw >= threshInt8) {
              // Dequantize confidence
              final boxConf = (boxConfRaw - zp) * scale;

              // Find best class
              // Iterate channels 5..84
              int maxClassId = -1;
              int maxClassRaw = -129;

              // Optimization: check if max class prob * box conf > threshold
              // In int8 loop
              for (int c = 0; c < 80; c++) {
                final clsChIdx = (a * 85) + 5 + c;
                final clsIdx = clsChIdx * gridLen + pixelIdx;
                if (clsIdx < data.length) {
                  final val = data[clsIdx];
                  if (val > maxClassRaw) {
                    maxClassRaw = val;
                    maxClassId = c;
                  }
                }
              }

              if (maxClassRaw >= threshInt8) {
                // Rough check
                final classProb = (maxClassRaw - zp) * scale;
                final score = boxConf * classProb;

                if (score > confThresh) {
                  // Dequantize box
                  // x, y, w, h are at indices 0, 1, 2, 3
                  final xRaw = data[((a * 85) + 0) * gridLen + pixelIdx];
                  final yRaw = data[((a * 85) + 1) * gridLen + pixelIdx];
                  final wRaw = data[((a * 85) + 2) * gridLen + pixelIdx];
                  final hRaw = data[((a * 85) + 3) * gridLen + pixelIdx];

                  double boxX = ((xRaw - zp) * scale) * 2.0 - 0.5;
                  double boxY = ((yRaw - zp) * scale) * 2.0 - 0.5;
                  double boxW = ((wRaw - zp) * scale) * 2.0;
                  double boxH = ((hRaw - zp) * scale) * 2.0;

                  boxX = (boxX + x) * stride;
                  boxY = (boxY + y) * stride;
                  boxW = (boxW * boxW) * anchorList[a * 2];
                  boxH = (boxH * boxH) * anchorList[a * 2 + 1];

                  double x1 = boxX - boxW / 2;
                  double y1 = boxY - boxH / 2;
                  double x2 = boxX + boxW / 2;
                  double y2 = boxY + boxH / 2;

                  // Convert from model space to original image space (stretch mode)
                  final stretchScaleW = inputSize / originalWidth.toDouble();
                  final stretchScaleH = inputSize / originalHeight.toDouble();

                  final x1Original = x1 / stretchScaleW;
                  final y1Original = y1 / stretchScaleH;
                  final x2Original = x2 / stretchScaleW;
                  final y2Original = y2 / stretchScaleH;

                  if (x1 >= 0 &&
                      y1 >= 0 &&
                      x2 <= inputSize &&
                      y2 <= inputSize) {
                    candidates.add(<double>[
                      x1Original,
                      y1Original,
                      x2Original,
                      y2Original,
                      score.toDouble(),
                      maxClassId.toDouble(),
                    ]);
                  }
                }
              }
            }
          }
        }
      }
    }

    // NMS using shared post-processor
    // Convert to Detection objects for NMS
    final detections = candidates.map((cand) {
      return Detection(
        x: (cand[0] + cand[2]) / 2, // center x from x1, x2
        y: (cand[1] + cand[3]) / 2, // center y from y1, y2
        width: cand[2] - cand[0], // width from x2 - x1
        height: cand[3] - cand[1], // height from y2 - y1
        classId: cand[5].toInt(),
        confidence: cand[4],
      );
    }).toList();

    final nmsResults = YoloPostProcessor.performNMS(detections);

    // Convert back to legacy list format [x1, y1, x2, y2, score, class]
    return nmsResults.map((det) {
      return [
        det.x - det.width / 2, // x1
        det.y - det.height / 2, // y1
        det.x + det.width / 2, // x2
        det.y + det.height / 2, // y2
        det.confidence,
        det.classId.toDouble(),
      ];
    }).toList();
  }

  // Note: _postProcessYolo() and _performNMS() have been removed.
  // These methods are now provided by the shared YoloProcessor utility class.
  // See lib/ai/post_processing/yolo_processor.dart for the implementation.
}
