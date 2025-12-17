import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:native_onnx/native_onnx.dart';
import 'dart:math' as math;

class InferenceService {
  static final InferenceService _instance = InferenceService._internal();
  factory InferenceService() => _instance;
  InferenceService._internal();

  final Map<String, NativeOrtSession> _sessions = {};

  Future<void> init() async {
    await NativeInferenceService().init();
  }

  Future<void> release() async {
    for (var s in _sessions.values) s.release();
    _sessions.clear();
  }

  Future<bool> loadModel(String modelPath) async {
    if (_sessions.containsKey(modelPath)) return true;
    try {
      // Assuming file exists or managed by caller (simplifying asset logic for now)
      final file = File(modelPath);
      if (!file.existsSync()) {
        // Add simplified asset copy logic if needed, or assume caller provides valid path
        // For now, assume path is valid for native bridge
      }

      final session = await NativeOrtSession.fromFile(file);
      _sessions[modelPath] = session;
      return true;
    } catch (e) {
      debugPrint("Load Model Failed: $e");
      return false;
    }
  }

  Future<List<dynamic>> runInference(
    String modelPath,
    Uint8List imageBytes,
    List<int> shape,
  ) async {
    var session = _sessions[modelPath];
    if (session == null) {
      await loadModel(modelPath);
      session = _sessions[modelPath];
      if (session == null) return [];
    }

    try {
      final Float32List floatList = await compute(_preprocessImage, imageBytes);

      final inputTensor = NativeOrtValueTensor.createTensorWithDataList(
        floatList,
        [1, 3, 640, 640],
      );

      final inputs = {'images': inputTensor};
      final runOptions = NativeOrtRunOptions();

      // NativeOrtSession.run returns List<List<dynamic>> (mimicking raw data return)
      // [ [dataList], [dataList2] ]
      final results = session.run(runOptions, inputs);

      inputTensor.release();

      if (results.isEmpty) return [];

      // Post Process YOLO
      // results[0][0] is the data list
      final outputData = results[0][0] as List<double>;

      return _postProcessYolo(outputData);
    } catch (e) {
      debugPrint("Generic Inference error: $e");
      return [];
    }
  }

  static Float32List _preprocessImage(Uint8List imageBytes) {
    final int width = 640;
    final int height = 640;
    final int inputChannels = 4;
    final int outputChannels = 3;

    if (imageBytes.length != width * height * inputChannels)
      return Float32List(0);

    final elementCount = outputChannels * width * height;
    final Float32List floatList = Float32List(elementCount);

    for (int c = 0; c < outputChannels; c++) {
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int srcOffset = (y * width + x) * inputChannels;
          final int dstOffset = c * (width * height) + y * width + x;
          floatList[dstOffset] = imageBytes[srcOffset + c] / 255.0;
        }
      }
    }
    return floatList;
  }

  List<dynamic> _postProcessYolo(List<double> data) {
    if (data.isEmpty) return [];

    // YOLOv8 shape [1, 84, 8400] flattened
    int rows = 84;
    int cols = 8400;

    if (data.length != rows * cols) {
      return [];
    }

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

        if (x1 >= 0 &&
            y1 >= 0 &&
            x2 > x1 &&
            y2 > y1 &&
            x2 <= 640 &&
            y2 <= 640) {
          candidates.add([x1, y1, x2, y2, maxScore, cls.toDouble()]);
        }
      }
    }
    return _nms(candidates);
  }

  List<dynamic> _nms(List<List<double>> boxes) {
    List<dynamic> results = [];
    boxes.sort((a, b) => b[4].compareTo(a[4]));
    while (boxes.isNotEmpty) {
      var current = boxes.removeAt(0);
      results.add(current);
      boxes.removeWhere((other) {
        double iou = _calculateIoU(current, other);
        return iou > 0.45;
      });
    }
    return results;
  }

  double _calculateIoU(List<double> a, List<double> b) {
    double xA = math.max(a[0], b[0]);
    double yA = math.max(a[1], b[1]);
    double xB = math.min(a[2], b[2]);
    double yB = math.min(a[3], b[3]);
    double interW = math.max(0, xB - xA);
    double interH = math.max(0, yB - yA);
    double interArea = interW * interH;
    double boxAArea = (a[2] - a[0]) * (a[3] - a[1]);
    double boxBArea = (b[2] - b[0]) * (b[3] - b[1]);
    return interArea / (boxAArea + boxBArea - interArea);
  }
}
