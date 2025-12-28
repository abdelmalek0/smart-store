import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
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
  // Configuration Constants - Optimized for Low Latency
  // ========================================
  // MAX_BATCH_SIZE: Set to 1 to disable batching for minimal latency
  // Each frame is processed immediately without waiting for batch collection
  static const int MAX_BATCH_SIZE = 1; // No batching for minimal latency
  static const int BATCH_WINDOW_MS = 10; // Immediate processing, no wait
  static const int QUEUE_SEARCH_LIMIT = 10; // Max items to search in queue
  static const int QUEUE_POLL_MS = 0; // Immediate polling for minimal latency

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
    Pointer<Float>? batchBuffer;

    // Capture when processing actually starts (excludes queue wait time)
    final processingStartMs = DateTime.now().millisecondsSinceEpoch;

    final totalStopwatch = Stopwatch()..start();
    final preprocessStopwatch = Stopwatch();
    final inferenceStopwatch = Stopwatch();
    final postprocessStopwatch = Stopwatch();

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
            final loadStart = Stopwatch()..start();
            session = await NativeOrtSession.fromFile(file);
            _sessions[modelPath] = session;
            debugPrint(
              "✓ Model loaded in ${loadStart.elapsedMilliseconds}ms. Total models: ${_sessions.length}",
            );
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
      preprocessStopwatch.start();

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

      preprocessStopwatch.stop();
      final preprocessMs = preprocessStopwatch.elapsedMilliseconds;

      // ========================================
      // Run Batch Inference
      // ========================================
      inferenceStopwatch.start();

      final inputTensor = NativeOrtValueTensor.createTensorFromPointer(
        batchBuffer,
        [batchSize, 3, 640, 640],
      );
      final inputs = {'images': inputTensor};
      final runOptions = NativeOrtRunOptions();

      try {
        final results = session.run(runOptions, inputs);

        inferenceStopwatch.stop();
        final inferenceMs = inferenceStopwatch.elapsedMilliseconds;

        // ========================================
        // Process Results
        // ========================================
        postprocessStopwatch.start();

        if (results.isNotEmpty) {
          final dynamic rawOutput = results[0][0];

          if (rawOutput is List<double> || rawOutput is List) {
            final List<double> data = (rawOutput is List<double>)
                ? rawOutput
                : (rawOutput as List).cast<double>();

            final int expectedSingleSize = 84 * 8400;
            final int expectedTotalSize = batchSize * expectedSingleSize;

            // Validate output size
            if (data.length != expectedTotalSize) {
              debugPrint(
                "⚠️ Output size mismatch: ${data.length} vs expected $expectedTotalSize",
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
            for (int i = 0; i < batchSize; i++) {
              final start = i * expectedSingleSize;
              final end = start + expectedSingleSize;
              _postProcessAndSend(
                data.sublist(start, end),
                batch[i],
                processingStartMs,
              );
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

        postprocessStopwatch.stop();
        final postprocessMs = postprocessStopwatch.elapsedMilliseconds;
        totalStopwatch.stop();
        final totalMs = totalStopwatch.elapsedMilliseconds;

        // Log detailed timing breakdown
        debugPrint(
          "⏱️ Batch[${batchSize}] timing: "
          "Preprocess=${preprocessMs}ms | "
          "Inference=${inferenceMs}ms | "
          "Postprocess=${postprocessMs}ms | "
          "Total=${totalMs}ms",
        );
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

  /// Post-process and send results for a single request
  void _postProcessAndSend(
    List<double> data,
    WorkerRequest req,
    int processingStartMs,
  ) {
    try {
      final detections = _postProcessYolo(data);
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
      debugPrint("⚠️ Postprocess error for stream ${req.streamId}: $e");
      mainSendPort.send(
        WorkerResponse(
          streamId: req.streamId,
          requestId: req.requestId,
          modelPath: req.modelPath,
          detections: [],
          error: "Postprocess: $e",
          processingStartMs: processingStartMs,
        ),
      );
    }
  }

  /// Post-process YOLO output - optimized for low latency
  /// Skips NMS for speed, returns top detections above threshold
  List<dynamic> _postProcessYolo(List<double> data) {
    int rows = 84;
    int cols = 8400;
    if (data.length != rows * cols) return [];

    List<List<double>> candidates = [];

    // Extract detections above confidence threshold
    for (int i = 0; i < cols; i++) {
      double maxScore = 0;
      int cls = -1;

      // Find class with highest confidence
      for (int c = 4; c < rows; c++) {
        int index = c * cols + i;
        double score = data[index];
        if (score > maxScore) {
          maxScore = score;
          cls = c - 4;
        }
      }

      // Use 0.5 threshold for good balance
      if (maxScore > 0.5) {
        double cx = data[0 * cols + i];
        double cy = data[1 * cols + i];
        double w = data[2 * cols + i];
        double h = data[3 * cols + i];
        double x1 = cx - w / 2;
        double y1 = cy - h / 2;
        double x2 = cx + w / 2;
        double y2 = cy + h / 2;

        // Validate bounding box is within frame
        if (x1 >= 0 && y1 >= 0 && x2 <= 640 && y2 <= 640) {
          candidates.add([x1, y1, x2, y2, maxScore, cls.toDouble()]);
        }
      }
    }

    // Sort by confidence and apply fast NMS
    candidates.sort((a, b) => b[4].compareTo(a[4]));

    List<dynamic> results = [];
    List<bool> suppressed = List.filled(candidates.length, false);

    for (int i = 0; i < candidates.length && results.length < 20; i++) {
      if (suppressed[i]) continue;

      var current = candidates[i];
      results.add(current);

      // Suppress overlapping boxes
      for (int j = i + 1; j < candidates.length; j++) {
        if (suppressed[j]) continue;

        var other = candidates[j];

        // Fast IoU calculation
        double xA = current[0] > other[0] ? current[0] : other[0];
        double yA = current[1] > other[1] ? current[1] : other[1];
        double xB = current[2] < other[2] ? current[2] : other[2];
        double yB = current[3] < other[3] ? current[3] : other[3];

        if (xA < xB && yA < yB) {
          double interArea = (xB - xA) * (yB - yA);
          double boxAArea =
              (current[2] - current[0]) * (current[3] - current[1]);
          double boxBArea = (other[2] - other[0]) * (other[3] - other[1]);
          double iou = interArea / (boxAArea + boxBArea - interArea);

          if (iou > 0.45) {
            suppressed[j] = true;
          }
        }
      }
    }

    return results;
  }
}
