import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'package:smart_store_linux/inference/messages.dart';

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
/// - Managing ONNX sessions for models
/// - Batching inference requests
/// - Running inference on GPU
/// - Post-processing YOLO outputs
class InferenceWorker {
  final SendPort mainSendPort;
  final ReceivePort _workerReceivePort = ReceivePort();
  final Map<String, NativeOrtSession> _sessions = {};
  final Queue<WorkerRequest> _requestQueue = Queue<WorkerRequest>();

  // ========================================
  // Configuration Constants
  // ========================================
  // MAX_BATCH_SIZE: Maximum number of frames to batch together for inference
  // Batchable models (e.g., YOLOv8) can process multiple frames in parallel on GPU
  // Higher batch size improves GPU utilization but increases latency
  static const int MAX_BATCH_SIZE =
      8; // Batch size optimized for RTX 2070 Super (8 streams)
  static const int BATCH_WINDOW_MS = 10; // Time window to collect batch items
  static const int QUEUE_SEARCH_LIMIT = 20; // Max items to search in queue
  static const int QUEUE_POLL_MS = 1; // Fast polling for low latency

  InferenceWorker(this.mainSendPort);

  /// Run the worker - initialize and start processing
  void run() async {
    // 1. Send Port IMMEDIATELY
    mainSendPort.send(_workerReceivePort.sendPort);
    debugPrint("Worker: Port Sent. Initializing Native Service...");

    try {
      await NativeInferenceService().init();
      debugPrint("Worker: Native Service Init Done. Sending Ready.");
      mainSendPort.send(WorkerReady(true));
    } catch (e) {
      debugPrint("Worker: Native Init Failed: $e");
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
    debugPrint("InferenceWorker: Starting Batch Loop");
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

      // LOG BATCH COMPOSITION
      final streamIdList = batch.map((r) => r.streamId).toList();
      debugPrint(
        "InferenceWorker: Processing batch size=${batch.length} streams=$streamIdList model=${firstReq.modelPath.split('/').last}",
      );
      await _processBatch(batch);
    }
  }

  /// Process a batch of inference requests
  Future<void> _processBatch(List<WorkerRequest> batch) async {
    final modelPath = batch.first.modelPath;
    Pointer<Float>? batchBuffer;

    try {
      // ========================================
      // Load Model Session
      // ========================================
      var session = _sessions[modelPath];
      if (session == null) {
        final file = File(modelPath);
        if (file.existsSync()) {
          try {
            debugPrint("📥 Loading model: ${modelPath.split('/').last}");
            session = await NativeOrtSession.fromFile(file);
            _sessions[modelPath] = session;
            debugPrint("✓ Model loaded. Total models: ${_sessions.length}");
          } catch (e) {
            debugPrint("❌ Model load error: $e");
          }
        }
        if (session == null) {
          _failBatch(batch, "Failed to load model $modelPath");
          return;
        }
      }

      // ========================================
      // Preprocess Images into Batch Buffer
      // ========================================
      final int batchSize = batch.length;
      final int singleImageFloats = 3 * 640 * 640;
      final int totalFloats = batchSize * singleImageFloats;

      batchBuffer = calloc<Float>(totalFloats);

      for (int i = 0; i < batchSize; i++) {
        final req = batch[i];
        final Pointer<Uint8> inPtr = calloc<Uint8>(req.imageBytes.length);
        final inList = inPtr.asTypedList(req.imageBytes.length);
        inList.setAll(0, req.imageBytes);

        final Pointer<Float> outPtr = Pointer.fromAddress(
          batchBuffer.address + (i * singleImageFloats * sizeOf<Float>()),
        );

        NativeInferenceService().preprocessImage(
          inPtr,
          req.width,
          req.height,
          outPtr,
        );
        calloc.free(inPtr);
      }

      // ========================================
      // Run Batch Inference
      // ========================================

      final inputTensor = NativeOrtValueTensor.createTensorFromPointer(
        batchBuffer,
        [batchSize, 3, 640, 640],
      );
      final inputs = {'images': inputTensor};
      final runOptions = NativeOrtRunOptions();

      try {
        debugPrint("🔄 Running inference for batch[$batchSize]...");
        final results = session.run(runOptions, inputs);
        debugPrint("✓ Inference complete. Results: ${results.length}");

        // ========================================
        // Process Results
        // ========================================
        if (results.isNotEmpty) {
          debugPrint(
            "  Result[0] type: ${results[0].runtimeType}, length: ${results[0] is List ? results[0].length : 'N/A'}",
          );
          final dynamic rawOutput = results[0][0];
          debugPrint(
            "  rawOutput type: ${rawOutput.runtimeType}, is List: ${rawOutput is List}",
          );

          if (rawOutput is List<double> || rawOutput is List) {
            final List<double> data = (rawOutput is List<double>)
                ? rawOutput
                : (rawOutput as List).cast<double>();

            final int expectedSingleSize = 84 * 8400;
            final int expectedTotalSize = batchSize * expectedSingleSize;

            // Validate output size
            if (data.length != expectedTotalSize) {
              debugPrint(
                "InferenceWorker: ERROR - Output size mismatch: ${data.length} vs expected $expectedTotalSize",
              );
              _failBatch(
                batch,
                "Output size mismatch: ${data.length} (expected $expectedTotalSize)",
              );
              return;
            }

            // ========================================
            // Split Batch Results to Individual Streams
            // ========================================
            debugPrint(
              "📤 Splitting batch[${batchSize}] -> ${batch.map((b) => b.streamId).join(', ')}",
            );
            for (int i = 0; i < batchSize; i++) {
              final start = i * expectedSingleSize;
              final end = start + expectedSingleSize;
              _postProcessAndSend(data.sublist(start, end), batch[i]);
            }
          } else {
            _failBatch(
              batch,
              "Unexpected output type: ${rawOutput.runtimeType}",
            );
          }
        } else {
          _failBatch(batch, "Empty Results from session.run");
        }
      } finally {
        inputTensor.release();
        runOptions.release();
      }
    } catch (e, st) {
      debugPrint("Worker Batch Error: $e\n$st");
      _failBatch(batch, e.toString());
    } finally {
      if (batchBuffer != null) calloc.free(batchBuffer);
    }
  }

  /// Fail a batch of requests
  void _failBatch(List<WorkerRequest> batch, String error) {
    for (var req in batch) {
      mainSendPort.send(
        WorkerResponse(
          streamId: req.streamId,
          requestId: req.requestId,
          modelPath: req.modelPath,
          detections: [],
          error: error,
        ),
      );
    }
  }

  /// Post-process and send results for a single request
  void _postProcessAndSend(List<double> data, WorkerRequest req) {
    try {
      final detections = _postProcessYolo(data);
      // LOG RESULT SENDING
      debugPrint(
        "InferenceWorker: Sending ${detections.length} detections for streamId=${req.streamId} reqId=${req.requestId}",
      );
      mainSendPort.send(
        WorkerResponse(
          streamId: req.streamId,
          requestId: req.requestId,
          modelPath: req.modelPath,
          detections: detections,
        ),
      );
    } catch (e) {
      debugPrint(
        "InferenceWorker: Postprocess error for streamId=${req.streamId}: $e",
      );
      mainSendPort.send(
        WorkerResponse(
          streamId: req.streamId,
          requestId: req.requestId,
          modelPath: req.modelPath,
          detections: [],
          error: "Postprocess: $e",
        ),
      );
    }
  }

  /// Post-process YOLO output with NMS
  List<dynamic> _postProcessYolo(List<double> data) {
    // ... (keep existing implementation)
    int rows = 84;
    int cols = 8400;
    if (data.length != rows * cols) return [];

    List<List<double>> candidates = [];

    for (int i = 0; i < cols; i++) {
      double maxScore = 0;
      int cls = -1;
      for (int c = 4; c < rows; c++) {
        int index = c * cols + i;
        double score = data[index];
        if (score > maxScore) {
          maxScore = score;
          cls = c - 4;
        }
      }

      if (maxScore > 0.45) {
        double cx = data[0 * cols + i];
        double cy = data[1 * cols + i];
        double w = data[2 * cols + i];
        double h = data[3 * cols + i];
        double x1 = cx - w / 2;
        double y1 = cy - h / 2;
        double x2 = cx + w / 2;
        double y2 = cy + h / 2;

        if (x1 >= 0 && y1 >= 0 && x2 <= 640 && y2 <= 640) {
          candidates.add([x1, y1, x2, y2, maxScore, cls.toDouble()]);
        }
      }
    }

    candidates.sort((a, b) => b[4].compareTo(a[4]));
    List<dynamic> results = [];
    while (candidates.isNotEmpty) {
      var current = candidates.removeAt(0);
      results.add(current);
      candidates.removeWhere((other) {
        double xA = math.max(current[0], other[0]);
        double yA = math.max(current[1], other[1]);
        double xB = math.min(current[2], other[2]);
        double yB = math.min(current[3], other[3]);
        double interW = math.max(0, xB - xA);
        double interH = math.max(0, yB - yA);
        double interArea = interW * interH;
        double boxAArea = (current[2] - current[0]) * (current[3] - current[1]);
        double boxBArea = (other[2] - other[0]) * (other[3] - other[1]);
        double iou = interArea / (boxAArea + boxBArea - interArea);
        return iou > 0.45;
      });
    }
    return results;
  }
}
