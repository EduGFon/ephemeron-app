import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings_provider.dart';

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
          const _SectionHeader('Appearance'),
          RadioGroup<ThemeModeOption>(
            groupValue: settings.themeMode,
            onChanged: (value) {
              if (value != null) notifier.setThemeMode(value);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeModeOption>(
                  title: Text('System'),
                  value: ThemeModeOption.system,
                ),
                RadioListTile<ThemeModeOption>(
                  title: Text('Light'),
                  value: ThemeModeOption.light,
                ),
                RadioListTile<ThemeModeOption>(
                  title: Text('Dark'),
                  value: ThemeModeOption.dark,
                ),
              ],
            ),
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
        ],
      ),
    );
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
