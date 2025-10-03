import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:device_info_plus/device_info_plus.dart';

class MIUIAutostartHelper {
  static const _prefsKey = 'miui_autostart_warning_shown';

  static Future<bool> _isXiaomiDevice() async {
    if (!Platform.isAndroid) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    final brand = info.brand?.toLowerCase() ?? '';
    final manufacturer = info.manufacturer?.toLowerCase() ?? '';
    return brand.contains('xiaomi') || manufacturer.contains('xiaomi') || brand.contains('redmi') || manufacturer.contains('redmi') || manufacturer.contains('poco');
  }

  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_prefsKey) ?? false;

    if (!shown && await _isXiaomiDevice()) {
      // ignore: use_build_context_synchronously
      await showDialog(
        context: context,
        builder: (_) => const _MIUIWarningDialog(),
      );
      prefs.setBool(_prefsKey, true);
    }
  }

  static Future<void> openAppSettings() async {
    final intent = AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:com.ermis', // ← replace with your package if different
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
  }
}

class _MIUIWarningDialog extends StatelessWidget {
  const _MIUIWarningDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Enable Autostart"),
      content: const Text(
        "Your phone is running MIUI (Xiaomi/Redmi/Poco).\n\n"
        "For reliable background location, you must enable Autostart for this app:\n\n"
        "1. Open device Settings.\n"
        "2. Tap Apps > Permissions > Autostart.\n"
        "3. Enable Autostart for Ermis.\n\n"
        "Otherwise, background location tracking may not work!"
      ),
      actions: [
        TextButton(
          onPressed: () {
            MIUIAutostartHelper.openAppSettings();
            Navigator.of(context).pop();
          },
          child: const Text("Open Settings"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Dismiss"),
        ),
      ],
    );
  }
}
