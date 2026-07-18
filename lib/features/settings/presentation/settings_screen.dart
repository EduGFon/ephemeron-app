import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../presentation/shell/pinned_sections_provider.dart';
import '../../auth/google/google_auth_provider.dart';
import '../../auth/google/google_auth_repository.dart';
import '../../sync/application/sync_service.dart';
import '../../../core/utils/dev_logger.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Google Account'),
          const _GoogleAccountTile(),
          const Divider(),
          const _SectionHeader('Appearance'),
          Consumer(
            builder: (context, ref, child) {
              final currentPalette = ref.watch(themeEngineProvider);
              return Column(
                children: [
                  const SizedBox(height: 8),
                  _ColorPickerRow(
                    title: 'Primary Color',
                    currentColor: currentPalette.primary,
                    options: const {
                      'Purple (Default)': Color(0xFF6C63FF),
                      'Pink': Colors.pink,
                      'Blue': Colors.blue,
                      'Cyan': Colors.cyan,
                      'Green': Colors.green,
                      'Yellow': Colors.yellow,
                      'Orange': Colors.orange,
                      'Red': Colors.red,
                      'Brown': Colors.brown,
                      'Monochromatic': Colors.grey,
                    },
                    onColorSelected: (c) => ref.read(themeEngineProvider.notifier).setPrimaryColor(c),
                    onCustomSelected: () => _editThemeColor(context, ref, 'Primary', currentPalette.primary),
                  ),
                  const SizedBox(height: 16),
                  _ColorPickerRow(
                    title: 'Background Color',
                    currentColor: currentPalette.background,
                    options: const {
                      'Obsidian (Default)': Color(0xFF121212),
                      'Black': Colors.black,
                      'Soft Dark': Color(0xFF1E1E1E),
                      'Soft Blue Dark': Color(0xFF171923),
                      'White': Colors.white,
                      'Off-White': Color(0xFFF7FAFC),
                    },
                    onColorSelected: (c) => ref.read(themeEngineProvider.notifier).setBackgroundColor(c),
                    onCustomSelected: () => _editThemeColor(context, ref, 'Background', currentPalette.background),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
          const Divider(),
          const _SectionHeader('Navigation Bar'),
          SwitchListTile(
            title: const Text('Floating Pill Layout'),
            subtitle: const Text('Use a floating glass navigation bar instead of edge-to-edge'),
            value: settings.usePillNavigation,
            onChanged: notifier.setUsePillNavigation,
          ),
          ListTile(
            title: const Text('Customize Navigation Bar'),
            subtitle: const Text('Reorder tabs and overflow items'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (context) => const _NavigationBarCustomizationSheet(),
              );
            },
          ),
          const Divider(),
          const _SectionHeader('Battery & motion'),
          SwitchListTile(
            title: const Text('Enable Glassmorphism (Blur Effects)'),
            subtitle: const Text(
              'Uses blurry backgrounds for some UI elements. WARNING: Severely impacts performance and battery usage.',
            ),
            value: settings.glassmorphismEnabled,
            onChanged: notifier.setGlassmorphismEnabled,
          ),
          SwitchListTile(
            title: const Text('Reduce animations'),
            subtitle: const Text('Turns off decorative page transitions'),
            value: settings.reducedMotion,
            onChanged: notifier.setReducedMotion,
          ),
          SwitchListTile(
            title: const Text('Power saving mode'),
            subtitle: const Text(
              'Manually force the same reduced-animation behavior',
            ),
            value: settings.powerSavingMode,
            onChanged: notifier.setPowerSavingMode,
          ),
          if (!kIsWeb)
            ListTile(
              title: const Text('Device battery saver'),
              subtitle: Text(
                settings.osBatterySaverActive
                    ? 'Currently on — Ephemeron is automatically reducing animations to match'
                    : 'Currently off',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Re-check',
                onPressed: notifier.refreshBatteryState,
              ),
            ),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _WebReminderNotice(),
            ),
          const Divider(),
          const _SectionHeader('Calendar'),
          ListTile(
            title: const Text('First day of the week'),
            subtitle: Text(_dayName(settings.calendarStartDay)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () {
              _showStartDayPicker(context, ref, settings.calendarStartDay);
            },
          ),
          const Divider(),
          const _SectionHeader('Sync & Caching'),
          const _SyncSettingsTile(),
          const Divider(),
          const _SectionHeader('Alarm Configuration'),
          ListTile(
            title: const Text('Short Alarm Sound Path'),
            subtitle: Text(settings.alarmShortSoundPath),
            trailing: const Icon(Icons.music_note, size: 20),
            onTap: () => _editSoundPath(context, ref, 'short', settings.alarmShortSoundPath),
          ),
          ListTile(
            title: const Text('Long Alarm Sound Path'),
            subtitle: Text(settings.alarmLongSoundPath),
            trailing: const Icon(Icons.music_note, size: 20),
            onTap: () => _editSoundPath(context, ref, 'long', settings.alarmLongSoundPath),
          ),
          ListTile(
            title: const Text('Alarm Screen Background'),
            subtitle: Row(
              children: [
                Container(
                  width: 24,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _parseColor(settings.alarmBackground),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(settings.alarmBackground),
              ],
            ),
            trailing: const Icon(Icons.color_lens, size: 20),
            onTap: () => _editAlarmBackground(context, ref, settings.alarmBackground),
          ),
          const Divider(),
          const _SectionHeader('Developer Tools'),
          ListTile(
            title: const Text('View developer logs'),
            subtitle: const Text('Check sync and authentication events / error messages'),
            trailing: const Icon(Icons.bug_report, size: 20),
            onTap: () {
              _showDevLogsDialog(context, ref);
            },
          ),
        ],
      ),
    );
   }

  static Color _parseColor(String hex) {
    try {
      var c = hex.replaceAll('#', '').trim();
      if (c.length == 6) {
        c = 'FF$c';
      }
      return Color(int.parse(c, radix: 16));
    } catch (_) {
      return const Color(0xFF005F73); // petrol default
    }
  }

  static void _editThemeColor(BuildContext context, WidgetRef ref, String type, Color current) {
    final hexString = '#${current.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    final controller = TextEditingController(text: hexString);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Custom $type Color', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '#FF6C63FF'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                try {
                  final color = _parseColor(val);
                  if (type == 'Primary') {
                    ref.read(themeEngineProvider.notifier).setPrimaryColor(color);
                  } else {
                    ref.read(themeEngineProvider.notifier).setBackgroundColor(color);
                  }
                } catch (_) {}
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static void _showDevLogsDialog(BuildContext context, WidgetRef ref) {
    final palette = ref.read(themeEngineProvider);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: palette.surface,
          surfaceTintColor: Colors.transparent,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Developer Logs', style: TextStyle(color: palette.text)),
              TextButton(
                onPressed: () {
                  DevLogger.clear();
                  Navigator.of(context).pop();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: DevLogger.logs.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet.',
                      style: TextStyle(color: palette.text.withValues(alpha: 0.5)),
                    ),
                  )
                : ListView.builder(
                    itemCount: DevLogger.logs.length,
                    itemBuilder: (context, index) {
                      final log = DevLogger.logs[DevLogger.logs.length - 1 - index];
                      final isError = log.error != null;
                      final timeStr = "${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isError 
                              ? Colors.redAccent.withValues(alpha: 0.1) 
                              : palette.text.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[$timeStr] ${log.message}',
                              style: TextStyle(
                                color: isError ? Colors.redAccent : palette.text,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            if (log.error != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Error: ${log.error}',
                                style: TextStyle(
                                  color: Colors.redAccent.shade200,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            if (log.stackTrace != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                log.stackTrace!,
                                style: TextStyle(
                                  color: palette.text.withValues(alpha: 0.4),
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                final text = DevLogger.logs.map((log) {
                  final timeStr = "${log.time.hour.toString().padLeft(2, '0')}:${log.time.minute.toString().padLeft(2, '0')}:${log.time.second.toString().padLeft(2, '0')}";
                  var msg = '[$timeStr] ${log.message}';
                  if (log.error != null) msg += '\nError: ${log.error}';
                  if (log.stackTrace != null) msg += '\nStackTrace: ${log.stackTrace}';
                  return msg;
                }).join('\n\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied to clipboard')),
                );
              },
              child: const Text('Copy Logs'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  static void _editSoundPath(BuildContext context, WidgetRef ref, String type, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Edit ${type == 'short' ? 'Short' : 'Long'} Alarm Sound Path', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '/path/to/sound.wav'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isNotEmpty) {
                if (type == 'short') {
                  ref.read(appSettingsProvider.notifier).setAlarmShortSoundPath(path);
                } else {
                  ref.read(appSettingsProvider.notifier).setAlarmLongSoundPath(path);
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static void _editAlarmBackground(BuildContext context, WidgetRef ref, String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Edit Alarm Background Hex Color', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '#005F73'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                ref.read(appSettingsProvider.notifier).setAlarmBackground(val);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static String _dayName(int isoDay) {
    const names = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };
    return names[isoDay] ?? 'Sunday';
  }

  static void _showStartDayPicker(BuildContext context, WidgetRef ref, int current) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('First day of the week', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              for (final day in [7, 1, 6]) // Sunday, Monday, Saturday — the common choices
                RadioListTile<int>(
                  title: Text(_dayName(day)),
                  value: day,
                  groupValue: current, // ignore: deprecated_member_use
                  onChanged: (value) { // ignore: deprecated_member_use
                    if (value != null) {
                      ref.read(appSettingsProvider.notifier).setCalendarStartDay(value);
                      Navigator.pop(sheetContext);
                    }
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _GoogleAccountTile extends ConsumerWidget {
  const _GoogleAccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(googleAccountProvider);

    return accountAsync.when(
      data: (account) {
        if (account == null) {
          return ListTile(
            leading: const Icon(Icons.account_circle_outlined, size: 40),
            title: const Text('Not connected'),
            subtitle: const Text('Sign in to sync Calendar & Tasks'),
            trailing: FilledButton(
              onPressed: () => _signIn(context, ref),
              child: const Text('Connect'),
            ),
          );
        }
        return ListTile(
          leading: account.photoUrl != null
              ? CircleAvatar(backgroundImage: NetworkImage(account.photoUrl!))
              : const Icon(Icons.account_circle, size: 40),
          title: Text(account.displayName ?? account.email),
          subtitle: Text(account.email),
          trailing: TextButton(
            onPressed: () => ref.read(googleAuthRepositoryProvider).signOut(),
            child: const Text('Disconnect'),
          ),
        );
      },
      loading: () => const ListTile(
        leading: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Checking connection...'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.error_outline, size: 40),
        title: const Text('Could not check Google status'),
        subtitle: Text('$error'),
        trailing: FilledButton(
          onPressed: () => _signIn(context, ref),
          child: const Text('Retry'),
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(googleAuthRepositoryProvider).signIn();
      // Pre-authorize Calendar + Tasks scopes together
      try {
        await ref.read(googleAuthRepositoryProvider).getAccessToken(const [
          AppConfig.googleCalendarScope,
          AppConfig.googleTasksScope,
        ]);
      } on Exception {
        // Swallowed — features will re-prompt individually if needed.
      }
      // Trigger sync immediately after successful sign-in
      unawaited(ref.read(syncServiceProvider.notifier).sync());
    } on GoogleAuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }
}


class _WebReminderNotice extends StatelessWidget {
  const _WebReminderNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reminders and alarms aren\'t available in the browser — this is a '
                'platform limitation (browsers don\'t support scheduled '
                'notifications), not a bug. Use the Android app for reminders.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _NavigationBarCustomizationSheet extends ConsumerWidget {
  const _NavigationBarCustomizationSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSections = ref.watch(allSectionsOrderProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Reorder Sections',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Drag to reorder. The top 5 appear on the bottom bar, the rest in "More".'),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: allSections.length,
              onReorderItem: (oldIndex, newIndex) {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                final item = allSections[oldIndex];
                final newList = List.of(allSections);
                newList.removeAt(oldIndex);
                newList.insert(newIndex, item);
                ref.read(allSectionsOrderProvider.notifier).updateOrder(newList);
              },
              itemBuilder: (context, index) {
                final section = allSections[index];
                final isPinned = index < 5;
                return ListTile(
                  key: ValueKey(section),
                  leading: Icon(isPinned ? section.icon : Icons.more_horiz),
                  title: Text(section.label),
                  trailing: const Icon(Icons.drag_handle),
                  tileColor: isPinned 
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncSettingsTile extends ConsumerWidget {
  const _SyncSettingsTile();

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final syncState = ref.watch(syncServiceProvider);
    final syncNotifier = ref.read(syncServiceProvider.notifier);

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Auto Sync'),
          subtitle: const Text('Synchronize events and tasks in the background'),
          value: settings.autoSync,
          onChanged: notifier.setAutoSync,
        ),
        if (settings.autoSync)
          ListTile(
            title: const Text('Sync Interval'),
            subtitle: const Text('How often the app refreshes in background'),
            trailing: DropdownButton<int>(
              value: settings.syncIntervalMinutes,
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
                DropdownMenuItem(value: 60, child: Text('1 hour')),
                DropdownMenuItem(value: 120, child: Text('2 hours')),
              ],
              onChanged: (val) {
                if (val != null) {
                  notifier.setSyncIntervalMinutes(val);
                }
              },
            ),
          ),
        ListTile(
          title: const Text('Manual Force Sync'),
          subtitle: syncState.lastSyncedAt != null
              ? Text('Last synced at ${_formatDateTime(syncState.lastSyncedAt!)}')
              : const Text('Never synced'),
          trailing: syncState.isSyncing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.icon(
                  onPressed: () async {
                    await syncNotifier.sync();
                    final current = ref.read(syncServiceProvider);
                    if (current.error != null && context.mounted) {
                      final palette = ref.read(themeEngineProvider);
                      showDialog( // ignore: unawaited_futures
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: palette.surface,
                          surfaceTintColor: Colors.transparent,
                          title: const Text('Sync Error'),
                          content: Text(current.error!),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                SettingsScreen._showDevLogsDialog(context, ref);
                              },
                              child: const Text('View Logs'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Sync Now'),
                ),
        ),
        if (syncState.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Sync error: ${syncState.error}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.title,
    required this.currentColor,
    required this.options,
    required this.onColorSelected,
    required this.onCustomSelected,
  });

  final String title;
  final Color currentColor;
  final Map<String, Color> options;
  final ValueChanged<Color> onColorSelected;
  final VoidCallback onCustomSelected;

  @override
  Widget build(BuildContext context) {
    final isCustom = !options.values.any((c) => c.toARGB32() == currentColor.toARGB32());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final entry in options.entries)
                InkWell(
                  onTap: () => onColorSelected(entry.value),
                  borderRadius: BorderRadius.circular(20),
                  child: Tooltip(
                    message: entry.key,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: currentColor.toARGB32() == entry.value.toARGB32()
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.grey.withValues(alpha: 0.5),
                          width: currentColor.toARGB32() == entry.value.toARGB32() ? 2 : 1,
                        ),
                      ),
                      child: currentColor.toARGB32() == entry.value.toARGB32()
                          ? Icon(Icons.check,
                              color: entry.value.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                          : null,
                    ),
                  ),
                ),
              InkWell(
                onTap: onCustomSelected,
                borderRadius: BorderRadius.circular(20),
                child: Tooltip(
                  message: 'Custom Hex',
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isCustom ? currentColor : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCustom
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.grey.withValues(alpha: 0.5),
                        width: isCustom ? 2 : 1,
                      ),
                    ),
                    child: isCustom
                        ? Icon(Icons.check,
                            color: currentColor.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                        : Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
