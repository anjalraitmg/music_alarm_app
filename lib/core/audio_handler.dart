import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';

late final AppAudioHandler audioHandler;

Future<void> initAudioHandler() async {
  audioHandler = await AudioService.init(
    builder: () => AppAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.music_alarm_app.audio',
      androidNotificationChannelName: 'Music Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class AppAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  final ValueNotifier<List<Track>> currentTracks = ValueNotifier([]);
  final ValueNotifier<Duration?> sleepRemaining = ValueNotifier(null);
  final ValueNotifier<bool> stopAfterCurrent = ValueNotifier(false);
  final ValueNotifier<bool> shuffleEnabled = ValueNotifier(false);
  final ValueNotifier<LoopMode> loopMode = ValueNotifier(LoopMode.off);

  Timer? _sleepTimer;
  bool _askedNotificationOnPlay = false;
  int? _lastIndex;

  AppAudioHandler() {
    player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    player.currentIndexStream.listen((index) async {
      final list = currentTracks.value;
      if (index != null && index >= 0 && index < list.length) {
        if (stopAfterCurrent.value && _lastIndex != null && _lastIndex != index) {
          stopAfterCurrent.value = false;
          await pause();
        }
        _lastIndex = index;
        mediaItem.add(list[index].toMediaItem());
      }
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && stopAfterCurrent.value) {
        stopAfterCurrent.value = false;
      }
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
      shuffleMode: shuffleEnabled.value
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.all: AudioServiceRepeatMode.all,
        LoopMode.one: AudioServiceRepeatMode.one,
      }[loopMode.value]!,
    );
  }

  Future<void> _ensureNotificationPermission() async {
    if (_askedNotificationOnPlay) return;
    _askedNotificationOnPlay = true;
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> setQueueAndPlay(List<Track> tracks, int initialIndex) async {
    if (tracks.isEmpty) return;
    await _ensureNotificationPermission();

    _lastIndex = null;
    currentTracks.value = List<Track>.from(tracks);
    queue.add(tracks.map((t) => t.toMediaItem()).toList());

    final sources = tracks.map((t) => AudioSource.file(t.path)).toList();
    await player.setAudioSources(
      sources,
      initialIndex: initialIndex.clamp(0, tracks.length - 1),
      initialPosition: Duration.zero,
    );
    mediaItem.add(tracks[initialIndex.clamp(0, tracks.length - 1)].toMediaItem());
    await play();
  }

  Future<void> playNext(Track track) async {
    final list = [...currentTracks.value];
    if (list.isEmpty) {
      await setQueueAndPlay([track], 0);
      return;
    }
    final insertIdx = (player.currentIndex ?? 0) + 1;
    list.insert(insertIdx, track);
    currentTracks.value = list;
    queue.add(list.map((t) => t.toMediaItem()).toList());
    await player.insertAudioSource(insertIdx, AudioSource.file(track.path));
  }

  Future<void> addToQueue(Track track) async {
    final list = [...currentTracks.value];
    if (list.isEmpty) {
      await setQueueAndPlay([track], 0);
      return;
    }
    list.add(track);
    currentTracks.value = list;
    queue.add(list.map((t) => t.toMediaItem()).toList());
    await player.addAudioSource(AudioSource.file(track.path));
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    final list = [...currentTracks.value];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (oldIndex < newIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= list.length) return;

    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    currentTracks.value = list;
    queue.add(list.map((t) => t.toMediaItem()).toList());
    await player.moveAudioSource(oldIndex, newIndex);
  }

  Future<void> toggleShuffle() async {
    final next = !shuffleEnabled.value;
    shuffleEnabled.value = next;
    await player.setShuffleModeEnabled(next);
    if (next) await player.shuffle();
  }

  Future<void> cycleRepeatMode() async {
    final next = switch (loopMode.value) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    loopMode.value = next;
    await player.setLoopMode(next);
  }

  // Sleep timer controls
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    sleepRemaining.value = duration;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final rem = sleepRemaining.value;
      if (rem == null) {
        timer.cancel();
        return;
      }
      final next = rem - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        timer.cancel();
        sleepRemaining.value = null;
        stopAfterCurrent.value = false;
        await pause();
      } else {
        sleepRemaining.value = next;
      }
    });
  }

  void extendSleepTimer(Duration extra) {
    final current = sleepRemaining.value;
    if (current != null) {
      sleepRemaining.value = current + extra;
    } else {
      startSleepTimer(extra);
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepRemaining.value = null;
    stopAfterCurrent.value = false;
  }

  void toggleStopAfterCurrent() {
    stopAfterCurrent.value = !stopAfterCurrent.value;
  }

  @override
  Future<void> play() async {
    await _ensureNotificationPermission();
    await player.play();
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    cancelSleepTimer();
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() => player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await player.seek(Duration.zero, index: index);
    await play();
  }
}