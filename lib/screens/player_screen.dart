import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../core/audio_handler.dart';
import '../core/models.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _dragSeconds;
  String? _artTrackId;
  Uint8List? _artworkBytes;

  // 1. The _fmt method is defined here, exactly once.
  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _loadArtworkIfNeeded(MediaItem? item) {
    if (item == null || item.id == _artTrackId) return;
    _artTrackId = item.id;
    final path = item.extras?['path'] as String?;
    if (path == null) {
      if (mounted) setState(() => _artworkBytes = null);
      return;
    }
    try {
      final meta = readMetadata(File(path), getImage: true);
      final bytes = meta.pictures.isNotEmpty ? meta.pictures.first.bytes : null;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _artworkBytes = bytes);
        });
      }
    } catch (_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _artworkBytes = null);
        });
      }
    }
  }

  void _openSleepTimerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sleep Timer',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                ValueListenableBuilder<Duration?>(
                  valueListenable: audioHandler.sleepRemaining,
                  builder: (_, rem, __) {
                    if (rem == null) return const SizedBox.shrink();
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.timer),
                        title: Text('Stopping in ${_fmt(rem)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => audioHandler
                                  .extendSleepTimer(const Duration(minutes: 10)),
                              child: const Text('+10m'),
                            ),
                            TextButton(
                              onPressed: audioHandler.cancelSleepTimer,
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...SleepTimerPreset.presets.map(
                      (p) => ActionChip(
                        label: Text(p.label),
                        onPressed: () {
                          audioHandler.startSleepTimer(p.duration);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    ActionChip(
                      label: const Text('Custom'),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _pickCustomSleepMinutes();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: audioHandler.stopAfterCurrent,
                  builder: (_, enabled, __) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stop after current track'),
                    value: enabled,
                    onChanged: (_) => audioHandler.toggleStopAfterCurrent(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustomSleepMinutes() async {
    final controller = TextEditingController(
      text: settingsNotifier.value.defaultSleepMinutes.toString(),
    );
    final mins = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom Sleep Timer (minutes)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(context, (v != null && v > 0) ? v : null);
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (mins != null) {
      audioHandler.startSleepTimer(Duration(minutes: mins));
    }
  }

  void _openQueueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollController) => ValueListenableBuilder<List<Track>>(
          valueListenable: audioHandler.currentTracks,
          builder: (context, tracks, __) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Queue (${tracks.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: scrollController,
                  itemCount: tracks.length,
                  onReorder: audioHandler.reorderQueue,
                  itemBuilder: (_, index) {
                    final t = tracks[index];
                    return ListTile(
                      key: ValueKey('${t.id}_$index'),
                      leading: const Icon(Icons.drag_handle),
                      title: Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(t.artist,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        audioHandler.skipToQueueItem(index);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        actions: [
          ValueListenableBuilder<Duration?>(
            valueListenable: audioHandler.sleepRemaining,
            builder: (_, rem, __) => IconButton(
              tooltip: 'Sleep Timer',
              icon: Badge(
                isLabelVisible: rem != null,
                label: Text(rem == null ? '' : '${rem.inMinutes + 1}m'),
                child: const Icon(Icons.timer_outlined),
              ),
              onPressed: _openSleepTimerSheet,
            ),
          ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music),
            onPressed: _openQueueSheet,
          ),
        ],
      ),
      body: StreamBuilder<MediaItem?>(
        stream: audioHandler.mediaItem,
        builder: (context, mediaSnap) {
          final item = mediaSnap.data;
          _loadArtworkIfNeeded(item);

          if (item == null) {
            return const Center(
              child: Text('Nothing playing. Pick a song from Library.'),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: _artworkBytes != null
                            ? Image.memory(_artworkBytes!, fit: BoxFit.cover)
                            : Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: const Icon(Icons.music_note, size: 96),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.artist ?? 'Unknown Artist'} • ${item.album ?? ''}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                StreamBuilder<Duration>(
                  stream: audioHandler.player.positionStream,
                  builder: (context, posSnap) {
                    final total =
                        audioHandler.player.duration ?? item.duration ?? Duration.zero;
                    final pos = posSnap.data ?? Duration.zero;
                    final maxSec = total.inSeconds.toDouble().clamp(1.0, double.infinity);
                    final currentSec = (_dragSeconds ?? pos.inSeconds.toDouble())
                        .clamp(0.0, maxSec);

                    return Column(
                      children: [
                        Slider(
                          value: currentSec,
                          max: maxSec,
                          onChanged: (v) => setState(() => _dragSeconds = v),
                          onChangeEnd: (v) async {
                            await audioHandler.seek(Duration(seconds: v.round()));
                            if (mounted) setState(() => _dragSeconds = null);
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(Duration(seconds: currentSec.round()))),
                            Text(_fmt(total)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                StreamBuilder<PlaybackState>(
                  stream: audioHandler.playbackState,
                  builder: (context, stateSnap) {
                    final playing = stateSnap.data?.playing ?? false;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: audioHandler.shuffleEnabled,
                          builder: (_, shuf, __) => IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              color: shuf
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            onPressed: audioHandler.toggleShuffle,
                          ),
                        ),
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: audioHandler.skipToPrevious,
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(18),
                          ),
                          onPressed:
                              playing ? audioHandler.pause : audioHandler.play,
                          child: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            size: 36,
                          ),
                        ),
                        IconButton(
                          iconSize: 36,
                          icon: const Icon(Icons.skip_next),
                          onPressed: audioHandler.skipToNext,
                        ),
                        ValueListenableBuilder<LoopMode>(
                          valueListenable: audioHandler.loopMode,
                          builder: (_, mode, __) => IconButton(
                            icon: Icon(
                              mode == LoopMode.one
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                              color: mode != LoopMode.off
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            onPressed: audioHandler.cycleRepeatMode,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}