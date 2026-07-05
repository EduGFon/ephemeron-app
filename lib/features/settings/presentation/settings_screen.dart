import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../presentation/shell/pinned_sections_provider.dart';

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
