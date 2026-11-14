import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/alarm_service.dart';
import 'core/audio_handler.dart';
import 'core/models.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final rawSettings = prefs.getString('app_settings_v1');
  if (rawSettings != null) {
    try {
      final jsonMap = jsonDecode(rawSettings) as Map<String, dynamic>;
      settingsNotifier.value = AppSettings.fromJson(jsonMap);
    } catch (_) {
      // Fallback to defaults if corrupted
      settingsNotifier.value = const AppSettings();
    }
  }

  await initAudioHandler();
  await alarmService.init(navigatorKey);

  runApp(const MusicAlarmApp());
}