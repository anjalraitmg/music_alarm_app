import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

/// Shared in-memory scanned tracks & app settings (no Drift/Riverpod).
final ValueNotifier<List<Track>> libraryTracks = ValueNotifier<List<Track>>([]);
final ValueNotifier<AppSettings> settingsNotifier =
    ValueNotifier<AppSettings>(const AppSettings());

enum LibrarySort { title, artist, dateAdded }

class Track {
  final String id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int dateAddedMs;

  const Track({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.dateAddedMs,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: durationMs > 0 ? duration : null,
        extras: {'path': path},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMs': durationMs,
        'dateAddedMs': dateAddedMs,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        path: json['path'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String? ?? 'Unknown Album',
        durationMs: json['durationMs'] as int? ?? 0,
        dateAddedMs: json['dateAddedMs'] as int? ?? 0,
      );
}

class Alarm {
  final int id;
  final int hour;
  final int minute;
  final String label;
  final bool enabled;
  final List<int> repeatDays; // 1=Mon .. 7=Sun; empty = Once
  final bool vibrate;
  final int snoozeMinutes;
  final bool fadeIn;
  final String? soundPath; // null = default alarm sound

  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = '',
    this.enabled = true,
    this.repeatDays = const [],
    this.vibrate = true,
    this.snoozeMinutes = 10,
    this.fadeIn = true,
    this.soundPath,
  });

  Alarm copyWith({
    int? id,
    int? hour,
    int? minute,
    String? label,
    bool? enabled,
    List<int>? repeatDays,
    bool? vibrate,
    int? snoozeMinutes,
    bool? fadeIn,
    String? soundPath,
    bool clearSoundPath = false,
  }) {
    return Alarm(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label ?? this.label,
      enabled: enabled ?? this.enabled,
      repeatDays: repeatDays ?? this.repeatDays,
      vibrate: vibrate ?? this.vibrate,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      fadeIn: fadeIn ?? this.fadeIn,
      soundPath: clearSoundPath ? null : (soundPath ?? this.soundPath),
    );
  }

  DateTime nextTriggerTime([DateTime? from]) {
    final now = from ?? DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);

    if (repeatDays.isEmpty) {
      if (!candidate.isAfter(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    for (int offset = 0; offset <= 7; offset++) {
      final day = candidate.add(Duration(days: offset));
      if (repeatDays.contains(day.weekday) && day.isAfter(now)) {
        return day;
      }
    }
    return candidate.add(const Duration(days: 1));
  }

  String formattedTime(BuildContext context) {
    return TimeOfDay(hour: hour, minute: minute).format(context);
  }

  String get repeatSummary {
    if (repeatDays.isEmpty) return 'Once';
    if (repeatDays.length == 7) return 'Daily';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = [...repeatDays]..sort();
    return sorted.map((d) => names[d - 1]).join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'enabled': enabled,
        'repeatDays': repeatDays,
        'vibrate': vibrate,
        'snoozeMinutes': snoozeMinutes,
        'fadeIn': fadeIn,
        'soundPath': soundPath,
      };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
        id: json['id'] as int,
        hour: json['hour'] as int,
        minute: json['minute'] as int,
        label: json['label'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        repeatDays: (json['repeatDays'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
        vibrate: json['vibrate'] as bool? ?? true,
        snoozeMinutes: json['snoozeMinutes'] as int? ?? 10,
        fadeIn: json['fadeIn'] as bool? ?? true,
        soundPath: json['soundPath'] as String?,
      );
}

class SleepTimerPreset {
  final String label;
  final Duration duration;

  const SleepTimerPreset(this.label, this.duration);

  static const List<SleepTimerPreset> presets = [
    SleepTimerPreset('15m', Duration(minutes: 15)),
    SleepTimerPreset('30m', Duration(minutes: 30)),
    SleepTimerPreset('1h', Duration(hours: 1)),
    SleepTimerPreset('2h', Duration(hours: 2)),
    SleepTimerPreset('3h', Duration(hours: 3)),
  ];
}

class AppSettings {
  final ThemeMode themeMode;
  final int defaultSnoozeMinutes;
  final int defaultSleepMinutes;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.defaultSnoozeMinutes = 10,
    this.defaultSleepMinutes = 30,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? defaultSnoozeMinutes,
    int? defaultSleepMinutes,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        defaultSnoozeMinutes:
            defaultSnoozeMinutes ?? this.defaultSnoozeMinutes,
        defaultSleepMinutes: defaultSleepMinutes ?? this.defaultSleepMinutes,
      );

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.index,
        'defaultSnoozeMinutes': defaultSnoozeMinutes,
        'defaultSleepMinutes': defaultSleepMinutes,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: ThemeMode.values[(json['themeMode'] as int? ?? 0)
            .clamp(0, ThemeMode.values.length - 1)],
        defaultSnoozeMinutes: json['defaultSnoozeMinutes'] as int? ?? 10,
        defaultSleepMinutes: json['defaultSleepMinutes'] as int? ?? 30,
      );
}