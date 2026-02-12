import 'dart:io' show Platform, exit;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:native_onnx/src/native_inference_service.dart';

import 'package:window_manager/window_manager.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/app_provider.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/core/resources/linux/linux_resource_monitor.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ai/service/inference_service.dart';
import 'package:smart_store_linux/ui/providers/inference_provider.dart';
import 'package:smart_store_linux/ui/screens/main_layout.dart';
import 'package:smart_store_linux/core/engine/stream_engine.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/resources/android/android_resource_monitor.dart'; // Add Android Monitor

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialize window_manager on desktop platforms
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
  }

  // Initialize Config Service
  await ConfigService.instance.init();

  if (Platform.isAndroid) {
    await _requestPermissions();
  }

  // Initialize Inference Service (ONNX Runtime) early to ensure Logger is registered
  await InferenceService().init();

  // Only configure window on desktop platforms
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    // Initialize Native Inference Service in Main Isolate
    // This allows the main thread to perform cleanup (videoRelease) and forceExit
    await NativeInferenceService().init();

    WindowOptions windowOptions = const WindowOptions(
      fullScreen: true,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const VisionLabApp());
}

class VisionLabApp extends StatefulWidget {
  const VisionLabApp({super.key});

  @override
  State<VisionLabApp> createState() => _VisionLabAppState();
}

class _VisionLabAppState extends State<VisionLabApp>
    with WidgetsBindingObserver, WindowListener {
  // Use dynamic or common interface if available, strictly typed limits swapping.
  // For now simple object as they don't share a base class in this refactor step.
  dynamic _monitor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Register window listener for proper shutdown
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
  }

  @override
  void onWindowClose() {
    debugPrint("[App] Window close requested - shutting down...");

    // 1. Shutdown resources
    _shutdownNativeResources();

    // 2. Force immediate exit from C++ side
    // This calls _Exit(0) which bypasses all static destructors
    debugPrint("[App] Calling native forceExit...");
    NativeInferenceService().forceExit();

    // 3. Fallback: If native exit didn't kill the process, we do it here
    debugPrint(
      "[App] Native force exit returned - falling back to Dart exit(0)",
    );
    exit(0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached) {
      _shutdownNativeResources();
    }
  }

  void _shutdownNativeResources() {
    debugPrint("[App] Shutting down native resources...");
    try {
      // 1. Stop high-level stream processing logic
      StreamEngine.instance.clearAll();

      // 2. Stop resource monitor
      _monitor?.stop();

      // 3. Shutdown low-level native resources
      NativeInferenceService().shutdown();

      debugPrint("[App] Native resources released successfully");
    } catch (e) {
      debugPrint("[App] Error releasing resources: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final provider = AppProvider();
            if (Platform.isAndroid) {
              _monitor = AndroidResourceMonitor(provider);
            } else {
              _monitor = LinuxResourceMonitor(provider);
            }
            _monitor.start();
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => RTSPStreamProvider()),
        ChangeNotifierProvider(
          create: (_) {
            final provider = ModelProvider();
            provider.initialize(); // Load persisted models
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<ModelProvider, InferenceProvider>(
          create: (_) => InferenceProvider(),
          update: (context, modelProvider, previous) {
            final provider = previous ?? InferenceProvider();
            provider.setModelProvider(modelProvider);
            // Only initialize once when both providers are ready
            if (modelProvider.isInitialized && !provider.isInitialized) {
              provider.initialize();
            }
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => StreamEngine()),
      ],
      child: MaterialApp(
        title: 'Smart Store',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainLayout(),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _monitor?.stop();
    _shutdownNativeResources();
    super.dispose();
  }
}

Future<void> _requestPermissions() async {
  debugPrint("Requesting permissions...");

  // Request Manage External Storage (Android 11+)
  if (await Permission.manageExternalStorage.request().isGranted) {
    debugPrint("Manage External Storage Granted");
  } else {
    debugPrint("Manage External Storage Denied");
  }

  // Request Legacy Storage (Android 10 and below)
  if (await Permission.storage.request().isGranted) {
    debugPrint("Storage Permission Granted");
  } else {
    debugPrint("Storage Permission Denied");
  }
}
