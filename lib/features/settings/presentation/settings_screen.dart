import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../presentation/shell/pinned_sections_provider.dart';
import '../../auth/google/google_auth_provider.dart';
import '../../auth/google/google_auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../sync/application/sync_service.dart';

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
          const _ConfigureGoogleCredentialsTile(),
          const Divider(),
          const _SectionHeader('Appearance (Premium Palettes)'),
          Consumer(
            builder: (context, ref, child) {
              final currentPalette = ref.watch(themeEngineProvider);
              return Column(
                children: AppPalette.values.map((palette) {
                  return RadioListTile<AppPaletteType>(
                    title: Text(palette.name),
                    value: palette.type,
                    groupValue: currentPalette.type,
                    onChanged: (value) {
                      if (value != null) ref.read(themeEngineProvider.notifier).setPalette(value);
                    },
                    secondary: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.background,
                        border: Border.all(color: palette.primary, width: 2),
                      ),
                    ),
                  );
                }).toList(),
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
                  groupValue: current,
                  onChanged: (value) {
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
    } on GoogleAuthCancelledException {
      // User backed out — normal, not an error.
    } on GoogleAuthException catch (e) {
      if (context.mounted) {
        if (e.message.contains('Client ID is not configured')) {
          unawaited(_ConfigureGoogleCredentialsTile._showCredentialsDialog(context));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    }
  }
}

class _ConfigureGoogleCredentialsTile extends ConsumerWidget {
  const _ConfigureGoogleCredentialsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb || !(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }

    return ListTile(
      leading: const Icon(Icons.settings_applications_outlined),
      title: const Text('Configure Custom Google Client ID'),
      subtitle: const Text('Required for Linux/Desktop Calendar sync'),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => unawaited(_showCredentialsDialog(context)),
    );
  }

  static Future<void> _showCredentialsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final idController = TextEditingController(text: prefs.getString('google.desktop.customClientId') ?? '');
    final secretController = TextEditingController(text: prefs.getString('google.desktop.customClientSecret') ?? '');

    if (!context.mounted) return;

    unawaited(showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google OAuth Credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your own Google OAuth Client ID and Secret for Desktop (type "Desktop application" in Google Cloud Console).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: idController,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                hintText: 'xxxx.apps.googleusercontent.com',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: secretController,
              decoration: const InputDecoration(
                labelText: 'Client Secret',
                hintText: 'Required by Google Cloud Console',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final id = idController.text.trim();
              final secret = secretController.text.trim();
              if (id.isNotEmpty && secret.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Client Secret is required when Client ID is provided.')),
                );
                return;
              }
              final prefs = await SharedPreferences.getInstance();
              if (id.isEmpty) {
                await prefs.remove('google.desktop.customClientId');
                await prefs.remove('google.desktop.customClientSecret');
              } else {
                await prefs.setString('google.desktop.customClientId', id);
                await prefs.setString('google.desktop.customClientSecret', secret);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ));
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
                  onPressed: syncNotifier.sync,
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

