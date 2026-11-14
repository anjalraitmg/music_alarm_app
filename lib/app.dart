import 'package:flutter/material.dart';
import 'main.dart';
import 'core/models.dart';
import 'screens/main_navigation.dart';
import 'screens/alarm_ringing_screen.dart';
import 'screens/player_screen.dart';
import 'screens/welcome_screen.dart';

class MusicAlarmApp extends StatelessWidget {
  final String initialRoute;

  const MusicAlarmApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSettings>(
      valueListenable: settingsNotifier,
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'Music Alarm',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          themeMode: settings.themeMode,
          initialRoute: initialRoute,
          routes: {
            '/': (context) => const MainNavigation(),
            '/welcome': (context) => const WelcomeScreen(),
            '/ring': (context) => const AlarmRingingScreen(),
            '/player': (context) => const PlayerScreen(),
          },
        );
      },
    );
  }
}