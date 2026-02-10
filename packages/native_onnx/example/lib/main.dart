import 'package:flutter/material.dart';
import 'package:native_onnx/src/native_inference_service.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _nativeOnnxPlugin = NativeInferenceService();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    bool isInitialized = false;
    try {
      await _nativeOnnxPlugin.init();
      isInitialized = true;
    } catch (e) {
      debugPrint("Init failed: $e");
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = isInitialized ? 'Initialized' : 'Failed to initialize';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Center(child: Text('Running on: $_platformVersion\n')),
      ),
    );
  }
}
