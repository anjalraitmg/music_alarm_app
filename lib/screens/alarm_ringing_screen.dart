import 'dart:async';
import 'package:flutter/material.dart';
import '../core/alarm_service.dart';
import '../core/models.dart';

class AlarmRingingScreen extends StatefulWidget {
  const AlarmRingingScreen({super.key});

  @override
  State<AlarmRingingScreen> createState() => _AlarmRingingScreenState();
}

class _AlarmRingingScreenState extends State<AlarmRingingScreen> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Alarm?>(
      valueListenable: alarmService.ringingAlarm,
      builder: (context, alarm, _) {
        final timeStr = TimeOfDay.fromDateTime(_now).format(context);
        final snoozeMin = alarm?.snoozeMinutes ?? 10;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      const Icon(Icons.alarm_on, size: 72),
                      const SizedBox(height: 16),
                      Text(timeStr, style: Theme.of(context).textTheme.displayLarge),
                      const SizedBox(height: 8),
                      Text(
                        (alarm?.label.isNotEmpty ?? false) ? alarm!.label : 'Alarm',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        onPressed: alarmService.stopRinging,
                        icon: const Icon(Icons.stop),
                        label: const Text('STOP', style: TextStyle(fontSize: 18)),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: alarmService.snoozeRinging,
                        icon: const Icon(Icons.snooze),
                        label: Text('SNOOZE ($snoozeMin min)', style: const TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}