import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/alarm_service.dart';
import 'core/audio_handler.dart';
import 'core/models.dart';
import 'screens/welcome_screen.dart'; // Import the new screen

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  
  // 1. Load settings
  final rawSettings = prefs.getString('app_settings_v1');
  if (rawSettings != null) {
    try {
      final jsonMap = jsonDecode(rawSettings) as Map<String, dynamic>;
      settingsNotifier.value = AppSettings.fromJson(jsonMap);
    } catch (_) {}
  }

  // 2. Safe init (so we don't crash)
  try {
    await initAudioHandler();
    await alarmService.init(navigatorKey);
  } catch (e) {
    debugPrint("Init error: $e");
  }

  // 3. Check if user saw welcome screen
  final hasSeenWelcome = prefs.getBool('has_seen_welcome') ?? false;

  // 4. Pass the starting route to the app
  runApp(MusicAlarmApp(
    initialRoute: hasSeenWelcome ? '/' : '/welcome',
  ));
}