import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../lua/plugin_host.dart';
import 'widgets.dart';

class PluginsScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  const PluginsScreen({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: pluginHost,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('plugins.title')),
          actions: [
            IconButton(
              tooltip: tr('plugins.reload'),
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await pluginHost.reload(ctrl);
                if (context.mounted) snack(context, tr('plugins.reload'));
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(tr('plugins.files'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (pluginHost.plugins.isEmpty)
              Text(tr('plugins.empty'))
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final p in pluginHost.plugins) Chip(label: Text(p)),
                ],
              ),
            const SizedBox(height: 24),
            Text(tr('plugins.actions'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (pluginHost.menu.isEmpty)
              Text(tr('plugins.noActions'))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in pluginHost.menu)
                    FilledButton.tonal(
                      onPressed: () {
                        pluginHost.runMenu(item);
                        snack(context, tr('plugins.done', {'label': item.label}));
                      },
                      child: Text(item.label),
                    ),
                ],
              ),
            const SizedBox(height: 24),
            Text(tr('plugins.log'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              pluginHost.logs.isEmpty ? '—' : pluginHost.logs.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}