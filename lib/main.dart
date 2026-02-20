import 'dart:io' show Platform, exit;
import 'package:flutter/material.dart';

import 'package:window_manager/window_manager.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';

import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/ui/view/screens/main_layout.dart';
import 'package:smart_store_linux/core/utils/permission_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize App Services (Config, System, Native Inference)
  await AppService.instance.init();

  if (Platform.isAndroid) {
    await PermissionUtils.requestAndroidPermissions();
  }

  // Only configure window on desktop platforms
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.maximize();
      await windowManager.focus();
    });
  }

  runApp(const SmartStoreApp());
}

class SmartStoreApp extends StatefulWidget {
  const SmartStoreApp({super.key});

  @override
  State<SmartStoreApp> createState() => _SmartStoreAppState();
}

class _SmartStoreAppState extends State<SmartStoreApp>
    with WidgetsBindingObserver, WindowListener {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Register window listener for proper shutdown
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.setPreventClose(true);
    }
  }

  @override
  void onWindowClose() {
    debugPrint("[App] Window close requested - shutting down...");

    // 1. Shutdown resources via AppService
    _shutdownApp();

    // 2. Force immediate exit
    debugPrint("[App] Calling native forceExit...");
    AppService.instance.forceExit();

    // 3. Fallback
    debugPrint(
      "[App] Native force exit returned - falling back to Dart exit(0)",
    );
    exit(0);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached) {
      _shutdownApp();
    }
  }

  void _shutdownApp() {
    AppService.instance.shutdown();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Store',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainLayout(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _shutdownApp();
    super.dispose();
  }
}
