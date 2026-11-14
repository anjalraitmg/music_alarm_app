import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const String _alarmsPrefsKey = 'saved_alarms_v1';
const String _alarmChannelId = 'alarm_ring_channel';
const String _alarmPortName = 'music_alarm_ring_port';

final AlarmService alarmService = AlarmService();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Handled when app brings itself to foreground or via launch details.
}

@pragma('vm:entry-point')
Future<void> alarmCallback(int id, Map<String, dynamic> params) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    settings: const InitializationSettings(android: androidInit),
  );

  final alarm = Alarm.fromJson(params);
  final title = alarm.label.isEmpty ? 'Alarm' : alarm.label;
  final body =
      '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}';

  final details = AndroidNotificationDetails(
    _alarmChannelId,
    'Alarms',
    channelDescription: 'Full-screen alarm alerts',
    importance: Importance.max,
    priority: Priority.max,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    ongoing: true,
    autoCancel: false,
    enableVibration: alarm.vibrate,
    actions: const [
      AndroidNotificationAction('stop', 'Stop', showsUserInterface: true),
      AndroidNotificationAction('snooze', 'Snooze', showsUserInterface: true),
    ],
  );

  await plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(android: details),
    payload: jsonEncode(params),
  );

  // If the main UI isolate is alive, notify it immediately.
  final SendPort? sendPort = IsolateNameServer.lookupPortByName(_alarmPortName);
  sendPort?.send(jsonEncode(params));
}

class AlarmService {
  final ValueNotifier<List<Alarm>> alarms = ValueNotifier([]);
  final ValueNotifier<Alarm?> ringingAlarm = ValueNotifier(null);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _ringPlayer = AudioPlayer();

  GlobalKey<NavigatorState>? _navKey;
  ReceivePort? _receivePort;
  Timer? _fadeTimer;
  Timer? _vibrateTimer;

  Future<void> init(GlobalKey<NavigatorState> navKey) async {
    _navKey = navKey;
    await AndroidAlarmManager.initialize();

    _receivePort?.close();
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_alarmPortName);
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, _alarmPortName);
    _receivePort!.listen((message) {
      if (message is String) {
        final alarm = Alarm.fromJson(jsonDecode(message) as Map<String, dynamic>);
        startRinging(alarm);
      }
    });

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    const channel = AndroidNotificationChannel(
      _alarmChannelId,
      'Alarms',
      description: 'Full-screen alarm alerts',
      importance: Importance.max,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await loadAlarms();
    await _rearmEnabledAlarms();

    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails!.notificationResponse;
      if (response != null) {
        _onNotificationResponse(response);
      }
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final alarm = Alarm.fromJson(jsonDecode(payload) as Map<String, dynamic>);

    if (response.actionId == 'stop') {
      ringingAlarm.value = alarm;
      stopRinging();
    } else if (response.actionId == 'snooze') {
      ringingAlarm.value = alarm;
      snoozeRinging();
    } else {
      startRinging(alarm);
    }
  }

  Future<void> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_alarmsPrefsKey);
    if (raw == null) {
      alarms.value = [];
      return;
    }
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => Alarm.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    alarms.value = list;
  }

  Future<void> saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(alarms.value.map((a) => a.toJson()).toList());
    await prefs.setString(_alarmsPrefsKey, encoded);
  }

  Future<void> _rearmEnabledAlarms() async {
    for (final alarm in alarms.value.where((a) => a.enabled)) {
      await _scheduleOneShot(alarm);
    }
  }

  Future<bool> _requestAlarmPermissions() async {
    final exactStatus = await Permission.scheduleExactAlarm.status;
    if (!exactStatus.isGranted) {
      await Permission.scheduleExactAlarm.request();
    }
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestFullScreenIntentPermission();
    return await Permission.scheduleExactAlarm.isGranted;
  }

  Future<void> scheduleAlarm(Alarm alarm) async {
    await _requestAlarmPermissions();
    await _scheduleOneShot(alarm);
  }

  Future<void> _scheduleOneShot(Alarm alarm) async {
    final triggerAt = alarm.nextTriggerTime();
    await AndroidAlarmManager.oneShotAt(
      triggerAt,
      alarm.id,
      alarmCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      alarmClock: true,
      rescheduleOnReboot: true,
      params: alarm.toJson(),
    );
  }

  Future<void> cancelAlarm(int id) async {
    await AndroidAlarmManager.cancel(id);
    await AndroidAlarmManager.cancel(id + 1000000); // snooze id
    await _notifications.cancel(id: id);
  }

  Future<void> upsertAlarm(Alarm alarm) async {
    final list = [...alarms.value];
    final idx = list.indexWhere((a) => a.id == alarm.id);
    if (idx >= 0) {
      list[idx] = alarm;
    } else {
      list.add(alarm);
    }
    list.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    alarms.value = list;
    await saveAlarms();

    if (alarm.enabled) {
      await scheduleAlarm(alarm);
    } else {
      await cancelAlarm(alarm.id);
    }
  }

  Future<void> toggleAlarm(Alarm alarm, bool enabled) async {
    await upsertAlarm(alarm.copyWith(enabled: enabled));
  }

  Future<void> deleteAlarm(int id) async {
    await cancelAlarm(id);
    alarms.value = alarms.value.where((a) => a.id != id).toList();
    await saveAlarms();
  }

  (Alarm, DateTime)? nextEnabledAlarm() {
    final enabled = alarms.value.where((a) => a.enabled).toList();
    if (enabled.isEmpty) return null;
    final now = DateTime.now();
    Alarm? best;
    DateTime? bestTime;
    for (final a in enabled) {
      final t = a.nextTriggerTime(now);
      if (bestTime == null || t.isBefore(bestTime)) {
        best = a;
        bestTime = t;
      }
    }
    if (best == null || bestTime == null) return null;
    return (best, bestTime);
  }

  Future<void> startRinging(Alarm alarm) async {
    ringingAlarm.value = alarm;
    _navKey?.currentState?.pushNamed('/ring');

    _fadeTimer?.cancel();
    _vibrateTimer?.cancel();

    try {
      await _ringPlayer.stop();
      if (alarm.soundPath != null) {
        await _ringPlayer.setAudioSource(AudioSource.file(alarm.soundPath!));
      } else {
        await _ringPlayer.setAudioSource(
          AudioSource.uri(Uri.parse('content://settings/system/alarm_alert')),
        );
      }
      await _ringPlayer.setLoopMode(LoopMode.one);
      if (alarm.fadeIn) {
        double vol = 0.05;
        await _ringPlayer.setVolume(vol);
        _fadeTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
          vol = (vol + (0.95 / 30)).clamp(0.05, 1.0);
          await _ringPlayer.setVolume(vol);
          if (vol >= 1.0) t.cancel();
        });
      } else {
        await _ringPlayer.setVolume(1.0);
      }
      await _ringPlayer.play();
    } catch (_) {
      // Fallback: notification channel alarm sound still rings.
    }

    if (alarm.vibrate) {
      _vibrateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        HapticFeedback.vibrate();
      });
    }
  }

  Future<void> stopRinging() async {
    final alarm = ringingAlarm.value;
    _fadeTimer?.cancel();
    _vibrateTimer?.cancel();
    await _ringPlayer.stop();
    if (alarm != null) {
      await _notifications.cancel(id: alarm.id);
      if (alarm.repeatDays.isEmpty) {
        await upsertAlarm(alarm.copyWith(enabled: false));
      } else {
        await _scheduleOneShot(alarm);
      }
    }
    ringingAlarm.value = null;
    if (_navKey?.currentState?.canPop() ?? false) {
      _navKey?.currentState?.pop();
    }
  }

  Future<void> snoozeRinging() async {
    final alarm = ringingAlarm.value;
    _fadeTimer?.cancel();
    _vibrateTimer?.cancel();
    await _ringPlayer.stop();
    if (alarm != null) {
      await _notifications.cancel(id: alarm.id);
      final snoozeTime =
          DateTime.now().add(Duration(minutes: alarm.snoozeMinutes));
      await AndroidAlarmManager.oneShotAt(
        snoozeTime,
        alarm.id + 1000000,
        alarmCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        alarmClock: true,
        params: alarm.toJson(),
      );
    }
    ringingAlarm.value = null;
    if (_navKey?.currentState?.canPop() ?? false) {
      _navKey?.currentState?.pop();
    }
  }
}