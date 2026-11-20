import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../core/xml_utils.dart';
import '../lua/plugin_host.dart';
import 'boss_screen.dart';
import 'plugins_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';
import 'package:xml/xml.dart';

class HomeScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  const HomeScreen({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, pluginHost]),
      builder: (context, _) {
        final all = ctrl.battles();
        final zones = ctrl.zones();
        final warriors = all.where((r) => ctrl.warriorOf(r.$2) != null).length;

        return PopScope(
          canPop: !ctrl.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final ok = await confirmDialog(context, tr('home.exitTitle'));
            if (ok && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(ctrl.dirty
                  ? '${tr('app.title')}  ●'
                  : tr('app.title')),
              actions: [
                IconButton(
                  tooltip: tr('home.search'),
                  icon: const Icon(Icons.search),
                  onPressed: () => showSearch(
                    context: context,
                    delegate: BossSearchDelegate(ctrl),
                  ),
                ),
                IconButton(
                  tooltip: tr('home.diagnostics'),
                  icon: const Icon(Icons.fact_check_outlined),
                  onPressed: () => _showDiagnostics(context),
                ),
              ],
            ),
            body: all.isEmpty
                ? Center(child: Text(tr('home.empty')))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Chip(label: Text('${tr('home.zones')}: ${zones.length}')),
                          Chip(label: Text('${tr('home.battles')}: ${all.length}')),
                          Chip(label: Text('${tr('home.warriors')}: $warriors')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final zone in zones)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            leading: const Icon(Icons.dns_outlined),
                            title: Text(zone.attr('Name', '?')),
                            subtitle: Text(zone.attr('FileName', '—')),
                            children: [
                              for (final b in zone.kids('Battle'))
                                _BattleTile(
                                  ctrl: ctrl,
                                  zone: zone,
                                  battle: b,
                                  index: all.indexWhere((r) => identical(r.$2, b)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
            bottomNavigationBar: BottomAppBar(
              height: 64,
              child: Row(
                children: [
                  IconButton(
                    tooltip: tr('home.undo', {'count': ctrl.undoCount, 'max': maxUndo}),
                    icon: Badge(
                      isLabelVisible: ctrl.undoCount > 0,
                      label: Text('${ctrl.undoCount}'),
                      child: const Icon(Icons.undo),
                    ),
                    onPressed: () {
                      if (!ctrl.undo()) snack(context, tr('err.undoEmpty'));
                    },
                  ),
                  IconButton(
                    tooltip: tr('home.save'),
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () => saveWithFeedback(context, ctrl),
                  ),
                  IconButton(
                    tooltip: tr('home.plugins'),
                    icon: const Icon(Icons.extension_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PluginsScreen(ctrl: ctrl)),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('home.settings'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      ctrl.dirty ? tr('home.dirty') : tr('toast.saved'),
                      key: ValueKey(ctrl.dirty),
                      style: TextStyle(
                        fontSize: 11,
                        color: ctrl.dirty
                            ? Theme.of(context).colorScheme.tertiary
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDiagnostics(BuildContext context) {
    final issues = ctrl.diagnostics();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          Text(tr('diag.title'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (issues.isEmpty)
            Text(tr('diag.ok'), style: const TextStyle(color: Colors.greenAccent)),
          for (final i in issues)
            ListTile(
              dense: true,
              leading: Icon(
                i.error ? Icons.error_outline : Icons.warning_amber,
                color: i.error ? Colors.redAccent : Colors.amber,
              ),
              title: Text(tr(i.key, i.args)),
            ),
        ],
      ),
    );
  }
}

class _BattleTile extends StatelessWidget {
  final RaidForgeController ctrl;
  final XmlElement zone;
  final XmlElement battle;
  final int index;

  const _BattleTile({
    required this.ctrl,
    required this.zone,
    required this.battle,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final w = ctrl.warriorOf(battle);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: const Icon(Icons.person, size: 18),
      ),
      title: Text(battle.attr('Name', 'UNKNOWN')),
      subtitle: Text(
        '${battle.attr('Title', tr('common.none'))} • '
        'PWR ${w?.attr('WarriorPower', '?') ?? '?'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BossScreen(ctrl: ctrl, index: index),
        ),
      ),
      onLongPress: () => _actions(context),
    );
  }

  void _actions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(tr('home.duplicate')),
              onTap: () async {
                Navigator.pop(c);
                final name = await showFieldsSheet(
                  context,
                  tr('home.duplicate'),
                  [FieldSpec('name', tr('sheet.name'), '${battle.attr('Name')}_COPY')],
                );
                if (name == null || !context.mounted) return;
                guard(context, () {
                  ctrl.duplicateBattle(zone, battle, name['name']!);
                  snack(context, tr('toast.duplicated'));
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text(tr('home.delete')),
              onTap: () async {
                Navigator.pop(c);
                if (await confirmDialog(context, '${tr('home.delete')}: ${battle.attr('Name')}?') &&
                    context.mounted) {
                  ctrl.deleteBattle(battle);
                  snack(context, tr('toast.deleted'));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BossSearchDelegate extends SearchDelegate<void> {
  final RaidForgeController ctrl;
  BossSearchDelegate(this.ctrl);

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => BackButton(
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    if (query.trim().isEmpty) {
      return Center(child: Text(tr('common.search')));
    }
    final all = ctrl.battles();
    final hits = ctrl.searchIndices(query);
    return ListView(
      children: [
        for (final i in hits)
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(all[i].$2.attr('Name', '?')),
            subtitle: Text('[${all[i].$1.attr('Name', '?')}] ${all[i].$2.attr('Title')}'),
            onTap: () {
              close(context, null);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BossScreen(ctrl: ctrl, index: i),
                ),
              );
            },
          ),
      ],
    );
  }
}