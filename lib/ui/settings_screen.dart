import 'package:flutter/material.dart';
import '../app_state.dart';
import '../core/l10n.dart';
import '../core/perk_source.dart';
import '../core/storage.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('settings.title'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr('settings.language'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'ru', label: Text('Русский')),
              ],
              selected: {appState.lang},
              onSelectionChanged: (s) => appState.setLang(s.first),
            ),
            const SizedBox(height: 24),
            Text(tr('settings.perkMode'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<PerkMergeMode>(
              segments: [
                ButtonSegment(
                  value: PerkMergeMode.replace,
                  label: Text(tr('perks.mode.replace')),
                  tooltip: tr('settings.perkMode.replace'),
                ),
                ButtonSegment(
                  value: PerkMergeMode.extend,
                  label: Text(tr('perks.mode.extend')),
                  tooltip: tr('settings.perkMode.extend'),
                ),
              ],
              selected: {appState.perkMode},
              onSelectionChanged: (s) => appState.setPerkMode(s.first),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.restore),
              label: Text(tr('settings.resetL10n')),
              onPressed: () async {
                await resetLocalisations();
                await L10n.load(appState.lang);
                if (context.mounted) snack(context, tr('settings.resetDone'));
              },
            ),
            const SizedBox(height: 24),
            Text(tr('settings.folders'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              [
                SfPaths.root,
                SfPaths.lua,
                SfPaths.save,
                SfPaths.consumables,
                SfPaths.localisations,
              ].join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}