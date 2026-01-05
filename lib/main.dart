import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:permission_handler/permission_handler.dart';

import 'package:window_manager/window_manager.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/providers/app_provider.dart';
import 'package:smart_store_linux/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/services/linux_resource_monitor.dart';
import 'package:smart_store_linux/providers/model_provider.dart';
import 'package:smart_store_linux/services/inference_service.dart';
import 'package:smart_store_linux/providers/inference_provider.dart';
import 'package:smart_store_linux/screens/main_layout.dart';
import 'package:smart_store_linux/services/stream_process_manager.dart';
import 'package:smart_store_linux/services/config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith();

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
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
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

class _VisionLabAppState extends State<VisionLabApp> {
  late LinuxResourceMonitor _monitor;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final provider = AppProvider();
            _monitor = LinuxResourceMonitor(provider);
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
        ChangeNotifierProvider(create: (_) => StreamProcessManager()),
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
    _monitor.stop();
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
