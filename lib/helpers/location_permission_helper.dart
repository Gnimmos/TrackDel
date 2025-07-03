import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationPermissionHelper {
  static Future<bool> ensureLocationPermissions(BuildContext context) async {
    while (true) {
      // Foreground location
      var status = await Permission.location.status;

      if (status.isGranted) {
        // Check background
        var bgStatus = await Permission.locationAlways.status;
        if (bgStatus.isGranted) {
          return true; // All set!
        } else {
          // Ask for background
          var result = await Permission.locationAlways.request();
          if (result.isGranted) return true;

          // Open settings with guidance
          bool opened = await _showGoToSettingsDialog(context,
               message: "To enable full delivery tracking, you must grant TrackDel 'Allow all the time' location access.\n\n"
                            "1. Tap 'Open Settings'.\n"
                            "2. Tap 'Permissions'.\n"
                            "3. Tap 'Location'.\n"
                            "4. Select 'Allow all the time' (or 'Always Allow').\n\n"
                            "If you don't see 'Allow all the time', select the most permissive option, then return to the app.",
);
          if (!opened) return false; // User canceled
          // If opened, loop to re-check after returning from settings
        }
      } else {
        // Request foreground location
        var result = await Permission.location.request();
        if (result.isGranted) {
          continue; // Now check background in the next loop
        } else if (result.isPermanentlyDenied) {
          // Guide to settings
          bool opened = await _showGoToSettingsDialog(context,
              message:
                  "TrackDel needs location permission to work.\n\nTap 'Open Settings' > Permissions > Location > Allow all the time.");
          if (!opened) return false;
        } else {
          // User denied, show again or just return
          bool retry = await _showRetryDialog(context,
              message: "You must allow location permission to use this app.");
          if (!retry) return false;
        }
      }
    }
  }

  static Future<bool> _showGoToSettingsDialog(BuildContext context,
      {String? message}) async {
    bool opened = false;
    await showDialog(
      context: context,
      barrierDismissible: false, // User must choose
      builder: (_) => AlertDialog(
        title: const Text("Permission Required"),
        content: Text(message ?? "Please enable location permissions in settings."),
        actions: [
          TextButton(
            onPressed: () {
              openAppSettings();
              opened = true;
              Navigator.of(context).pop();
            },
            child: const Text("Open Settings"),
          ),
          TextButton(
            onPressed: () {
              opened = false;
              Navigator.of(context).pop();
            },
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
    return opened;
  }

  static Future<bool> _showRetryDialog(BuildContext context,
      {required String message}) async {
    bool retry = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Permission Needed"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              retry = true;
              Navigator.of(context).pop();
            },
            child: const Text("Retry"),
          ),
          TextButton(
            onPressed: () {
              retry = false;
              Navigator.of(context).pop();
            },
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
    return retry;
  }
}
