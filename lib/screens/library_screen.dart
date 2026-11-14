import 'dart:io';
import 'dart:convert';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio_handler.dart';
import '../core/models.dart';

const String _foldersPrefsKey = 'music_folders_v1';
const String _settingsPrefsKey = 'app_settings_v1';
const Set<String> _supportedExts = {
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.ogg',
  '.wav',
  '.opus',
};

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<String> _folders = [];
  bool _scanning = false;
  String _search = '';
  LibrarySort _sort = LibrarySort.title;

  @override
  void initState() {
    super.initState();
    _loadFoldersAndScan();
  }

  Future<void> _loadFoldersAndScan() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_foldersPrefsKey) ?? [];
    setState(() => _folders = saved);
    if (saved.isNotEmpty) {
      await _scanFolders();
    }
  }

  Future<bool> _requestAudioPermission() async {
    if (await Permission.audio.isGranted || await Permission.storage.isGranted) {
      return true;
    }
    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted) return true;
    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  Future<void> _addFolder() async {
    final granted = await _requestAudioPermission();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio storage permission is needed.')),
      );
      return;
    }

    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    if (_folders.contains(path)) return;

    final updated = [..._folders, path];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_foldersPrefsKey, updated);
    setState(() => _folders = updated);
    await _scanFolders();
  }

  Future<void> _removeFolder(String path) async {
    final updated = _folders.where((f) => f != path).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_foldersPrefsKey, updated);
    setState(() => _folders = updated);
    await _scanFolders();
  }

  Future<void> _scanFolders() async {
    setState(() => _scanning = true);
    final List<Track> found = [];
    final Set<String> seenPaths = {};

    for (final folder in _folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final lower = entity.path.toLowerCase();
          final ok = _supportedExts.any((ext) => lower.endsWith(ext));
          if (!ok || seenPaths.contains(entity.path)) continue;
          seenPaths.add(entity.path);

          final fileName = entity.uri.pathSegments.last;
          final fallbackTitle = fileName.contains('.')
              ? fileName.substring(0, fileName.lastIndexOf('.'))
              : fileName;

          String title = fallbackTitle;
          String artist = 'Unknown Artist';
          String album = 'Unknown Album';
          int durationMs = 0;
          int modifiedMs = 0;

          try {
            final stat = await entity.stat();
            modifiedMs = stat.modified.millisecondsSinceEpoch;
            final meta = readMetadata(entity, getImage: false);
            if ((meta.title ?? '').trim().isNotEmpty) {
              title = meta.title!.trim();
            }
            if ((meta.artist ?? '').trim().isNotEmpty) {
              artist = meta.artist!.trim();
            }
            if ((meta.album ?? '').trim().isNotEmpty) {
              album = meta.album!.trim();
            }
            if (meta.duration != null) {
              durationMs = meta.duration!.inMilliseconds;
            }
          } catch (_) {
            // Unreadable tags: keep filename fallback.
          }

          found.add(Track(
            id: entity.path,
            path: entity.path,
            title: title,
            artist: artist,
            album: album,
            durationMs: durationMs,
            dateAddedMs: modifiedMs,
          ));
        }
      } catch (_) {
        // Skip unreadable directory.
      }
    }

    libraryTracks.value = found;
    if (mounted) {
      setState(() => _scanning = false);
    }
  }

  List<Track> _filteredAndSorted(List<Track> all) {
    final q = _search.trim().toLowerCase();
    final filtered = q.isEmpty
        ? [...all]
        : all
            .where((t) =>
                t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q))
            .toList();

    filtered.sort((a, b) => switch (_sort) {
          LibrarySort.title =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          LibrarySort.artist =>
            a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
          LibrarySort.dateAdded => b.dateAddedMs.compareTo(a.dateAddedMs),
        });
    return filtered;
  }

  String _fmtDuration(Duration d) {
    if (d <= Duration.zero) return '--:--';
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showTrackMenu(Track track) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('Play next'),
              onTap: () {
                Navigator.pop(context);
                audioHandler.playNext(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Playing "${track.title}" next')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('Add to queue'),
              onTap: () {
                Navigator.pop(context);
                audioHandler.addToQueue(track);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added "${track.title}" to queue')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

    void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (_) => ValueListenableBuilder<AppSettings>(
        valueListenable: settingsNotifier,
        builder: (context, settings, __) => AlertDialog(
          title: const Text('Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 👇 App Logo
                Center(
                  child: Image.asset(
                    'assets/logo.png',
                    height: 80,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.music_note, size: 80), // Fallback if image is missing
                  ),
                ),
                const SizedBox(height: 16),
                
                const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (sel) => _saveSettings(
                    settings.copyWith(themeMode: sel.first),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: settings.defaultSnoozeMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Default snooze duration',
                    border: OutlineInputBorder(),
                  ),
                  items: const [5, 10, 15]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _saveSettings(settings.copyWith(defaultSnoozeMinutes: v));
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: settings.defaultSleepMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Default sleep timer',
                    border: OutlineInputBorder(),
                  ),
                  items: const [15, 30, 60, 120]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      _saveSettings(settings.copyWith(defaultSleepMinutes: v));
                    }
                  },
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Permission.ignoreBatteryOptimizations.request();
                  },
                  icon: const Icon(Icons.battery_saver),
                  label: const Text('Disable battery optimization'),
                ),
                const Divider(height: 32),
                
                // 👇 Support Section (QR Code)
                const Center(
                  child: Text(
                    'Support the Developer',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: InkWell(
                    onTap: () {
                      // Optional: Show the QR code full screen if tapped
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          child: Image.asset('assets/qr_code.jpeg'),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/qr_code.jpeg',
                        height: 150,
                        errorBuilder: (context, error, stackTrace) =>
                            const Text('QR Code missing'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // 👇 Footer text
                const Center(
                  child: Text(
                    'v1.0\nMade with ❤️',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings(AppSettings updated) async {
  settingsNotifier.value = updated;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_settingsPrefsKey, jsonEncode(updated.toJson()));
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'Add Folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _scanning ? null : _addFolder,
          ),
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh),
            onPressed: _scanning || _folders.isEmpty ? null : _scanFolders,
          ),
          PopupMenuButton<LibrarySort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: LibrarySort.title, child: Text('Sort by Title')),
              PopupMenuItem(value: LibrarySort.artist, child: Text('Sort by Artist')),
              PopupMenuItem(
                value: LibrarySort.dateAdded,
                child: Text('Sort by Date Added'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Track>>(
        valueListenable: libraryTracks,
        builder: (context, allTracks, _) {
          if (_scanning) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Scanning music folders...'),
                ],
              ),
            );
          }

          if (_folders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open, size: 64),
                    const SizedBox(height: 12),
                    const Text(
                      'No folders added. Tap + to add music.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addFolder,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Folder'),
                    ),
                  ],
                ),
              ),
            );
          }

          final tracks = _filteredAndSorted(allTracks);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search title or artist',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: _folders.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final folder = _folders[i];
                    final name = folder.split('/').where((s) => s.isNotEmpty).last;
                    return InputChip(
                      label: Text(name),
                      onDeleted: () => _removeFolder(folder),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '${allTracks.length} songs in ${_folders.length} folders',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tracks.isEmpty
                    ? const Center(child: Text('No matching songs.'))
                    : ListView.builder(
                        itemCount: tracks.length,
                        itemBuilder: (context, index) {
                          final track = tracks[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.music_note),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${track.artist} • ${_fmtDuration(track.duration)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () async {
                              await audioHandler.setQueueAndPlay(tracks, index);
                              if (context.mounted) {
                                Navigator.pushNamed(context, '/player');
                              }
                            },
                            onLongPress: () => _showTrackMenu(track),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}