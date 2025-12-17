import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'package:window_manager/window_manager.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/providers/app_provider.dart';
import 'package:smart_store_linux/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/services/linux_resource_monitor.dart';
import 'package:smart_store_linux/providers/model_provider.dart';
import 'package:smart_store_linux/services/inference_service.dart';
import 'package:smart_store_linux/providers/inference_provider.dart';
import 'package:smart_store_linux/screens/main_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith();

  await windowManager.ensureInitialized();

  // Initialize Inference Service (ONNX Runtime) early to ensure Logger is registered
  await InferenceService().init();

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
        ChangeNotifierProvider(create: (_) => InferenceProvider()),
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
