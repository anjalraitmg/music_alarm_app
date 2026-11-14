import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // to access navigatorKey

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _requestPermissions(BuildContext context) async {
    // 1. Ask for Notification permission (For playback controls & alarms)
    await Permission.notification.request();
    
    // 2. Ask for Audio permission (To read your music folders)
    await Permission.audio.request();

    // 3. Ask for Exact Alarms (Crucial for waking you up on time)
    await Permission.scheduleExactAlarm.request();

    // 4. Optional but highly recommended for alarms: Battery Optimization
    // (Without this, Android might kill the alarm to save battery)
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // Save that we asked, so we don't show this screen again
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_welcome', true);

    // Navigate to the main app
    navigatorKey.currentState?.pushReplacementNamed('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/logo.png', height: 100), // Your logo
              const SizedBox(height: 24),
              Text(
                'Welcome to Music Alarm',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'To ensure your alarms wake you up reliably and we can find your music, the app needs a few permissions.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _requestPermissions(context),
                child: const Text('Allow Permissions & Continue', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}