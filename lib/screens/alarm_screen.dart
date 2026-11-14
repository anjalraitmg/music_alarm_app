import 'dart:async';

import 'package:flutter/material.dart';

import '../core/alarm_service.dart';
import '../core/models.dart';

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  String _nextBannerText(BuildContext context) {
    final next = alarmService.nextEnabledAlarm();
    if (next == null) return 'No upcoming alarms';
    final (alarm, time) = next;
    final diff = time.difference(DateTime.now());
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return 'Next alarm: ${alarm.formattedTime(context)}, in ${h}h ${m}m';
  }

  Future<void> _openEditor(BuildContext context, [Alarm? existing]) async {
    TimeOfDay picked = existing != null
        ? TimeOfDay(hour: existing.hour, minute: existing.minute)
        : TimeOfDay.now();
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    List<int> repeatDays = [...(existing?.repeatDays ?? [])];
    bool vibrate = existing?.vibrate ?? true;
    int snoozeMin =
        existing?.snoozeMinutes ?? settingsNotifier.value.defaultSnoozeMinutes;
    bool fadeIn = existing?.fadeIn ?? true;
    String? soundPath = existing?.soundPath;

    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final saved = await showDialog<Alarm>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Alarm' : 'Edit Alarm'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: picked,
                      );
                      if (t != null) setDialogState(() => picked = t);
                    },
                    child: Text(
                      picked.format(context),
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                ),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Repeat'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Once'),
                      selected: repeatDays.isEmpty,
                      onSelected: (_) => setDialogState(() => repeatDays = []),
                    ),
                    ChoiceChip(
                      label: const Text('Daily'),
                      selected: repeatDays.length == 7,
                      onSelected: (_) =>
                          setDialogState(() => repeatDays = [1, 2, 3, 4, 5, 6, 7]),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: List.generate(7, (i) {
                    final day = i + 1;
                    final selected = repeatDays.contains(day);
                    return FilterChip(
                      label: Text(dayLabels[i]),
                      selected: selected,
                      onSelected: (v) {
                        setDialogState(() {
                          if (v) {
                            repeatDays.add(day);
                          } else {
                            repeatDays.remove(day);
                          }
                        });
                      },
                    );
                  }),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vibrate'),
                  value: vibrate,
                  onChanged: (v) => setDialogState(() => vibrate = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fade-in volume (30s)'),
                  value: fadeIn,
                  onChanged: (v) => setDialogState(() => fadeIn = v),
                ),
                DropdownButtonFormField<int>(
                  value: snoozeMin,
                  decoration: const InputDecoration(
                    labelText: 'Snooze duration',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [5, 10, 15]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => snoozeMin = v);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sound'),
                  subtitle: Text(
                    soundPath == null
                        ? 'Default alarm'
                        : soundPath!.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final chosen = await _pickSoundDialog(context, soundPath);
                      if (chosen != null) {
                        setDialogState(
                          () => soundPath = chosen.isEmpty ? null : chosen,
                        );
                      }
                    },
                    child: const Text('Choose'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final id = existing?.id ??
                    (DateTime.now().millisecondsSinceEpoch % 100000000);
                Navigator.pop(
                  context,
                  Alarm(
                    id: id,
                    hour: picked.hour,
                    minute: picked.minute,
                    label: labelCtrl.text.trim(),
                    enabled: true,
                    repeatDays: repeatDays,
                    vibrate: vibrate,
                    snoozeMinutes: snoozeMin,
                    fadeIn: fadeIn,
                    soundPath: soundPath,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != null) {
      await alarmService.upsertAlarm(saved);
    }
  }

  Future<String?> _pickSoundDialog(BuildContext context, String? current) {
    final tracks = libraryTracks.value;
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Alarm Sound'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.alarm),
                title: const Text('Default alarm'),
                selected: current == null,
                onTap: () => Navigator.pop(context, ''),
              ),
              const Divider(),
              if (tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Scan music folders in Library to pick a song.'),
                )
              else
                ...tracks.map(
                  (t) => ListTile(
                    leading: const Icon(Icons.music_note),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.artist,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: current == t.path,
                    onTap: () => Navigator.pop(context, t.path),
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
      appBar: AppBar(title: const Text('Alarms')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add Alarm'),
      ),
      body: ValueListenableBuilder<List<Alarm>>(
        valueListenable: alarmService.alarms,
        builder: (context, list, _) {
          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _nextBannerText(context),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Text('No alarms set. Tap + to add one.'))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final alarm = list[index];
                          return Dismissible(
                            key: ValueKey(alarm.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => alarmService.deleteAlarm(alarm.id),
                            child: ListTile(
                              title: Text(
                                alarm.formattedTime(context),
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              subtitle: Text(
                                '${alarm.label.isEmpty ? 'Alarm' : alarm.label} • ${alarm.repeatSummary}',
                              ),
                              trailing: Switch(
                                value: alarm.enabled,
                                onChanged: (v) =>
                                    alarmService.toggleAlarm(alarm, v),
                              ),
                              onTap: () => _openEditor(context, alarm),
                              onLongPress: () =>
                                  alarmService.deleteAlarm(alarm.id),
                            ),
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

