import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  /// Request necessary permissions on Android.
  static Future<void> requestAndroidPermissions() async {
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
}
