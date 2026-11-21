import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/config.dart';
import '../common/dialogs.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../search/search_screen.dart';
import '../zone/zone_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final st = ctrl.statistics();
        final zs = ctrl.zones();

        return PopScope(
          canPop: !ctrl.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;

            final ok = await confirm(
              context,
              'Есть несохранённые изменения. Выйти без сохранения?',
            );

            if (ok && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                ctrl.dirty
                    ? 'RAID FORGE  ● изменён'
                    : 'RAID FORGE',
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'diag') {
                      go(context, const DiagnosticsScreen());
                    }

                    if (v == 'about') {
                      showAboutDialog(
                        context: context,
                        applicationName: 'SF2 Raid Forge',
                        children: const [
                          Text(
                            'XML-редактор raid_stages.\n\n'
                            'Zones / Battles, Warrior, Perks, Rules, '
                            'EquipItem, ComplexRules, RulesWithConditions, '
                            'Rewards, поиск, undo, диагностика, '
                            'сохранение с backup.',
                          ),
                        ],
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'diag',
                      child: Text('Проверить XML'),
                    ),
                    PopupMenuItem(
                      value: 'about',
                      child: Text('О программе'),
                    ),
                  ],
                ),
              ],
            ),

            // ------------------------------------------------
            // MAIN CONTENT
            // ------------------------------------------------

            body: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final e in {
                        'Zones': st.zones,
                        'Battles': st.battles,
                        'Warriors': st.warriors,
                        'Warrior Perks': st.warriorPerks,
                        'ComplexRules': st.complexRules,
                        'EquipItems': st.equipItems,
                        'Rule-Perks': st.rulePerks,
                        'Currencies': st.currencies,
                        'Conditions': st.conditions,
                      }.entries)
                        Chip(
                          label: Text('${e.key}: ${e.value}'),
                        ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                if (zs.isEmpty)
                  emptyNote('Зон нет.'),

                for (final zone in zs)
                  ListTile(
                    leading: const Icon(Icons.dns),
                    title: Text(zone.attr('Name', '?')),
                    subtitle: Text(
                      '${zone.attr('FileName', 'N/A')} • '
                      '${zone.kids('Battle').length} battles',
                    ),
                    onTap: () => go(
                      context,
                      ZoneScreen(zone),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          final r = await form(
                            context,
                            'Зона',
                            {
                              'Name': zone.attr('Name'),
                              'FileName': zone.attr('FileName'),
                            },
                          );

                          if (r != null) {
                            ctrl.editZone(
                              zone,
                              r['Name']!,
                              r['FileName']!,
                            );
                          }
                        } else if (v == 'del') {
                          if (await confirm(
                            context,
                            'Удалить зону ${zone.attr('Name')}?',
                          )) {
                            ctrl.deleteZone(zone);
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Переименовать / изменить'),
                        ),
                        PopupMenuItem(
                          value: 'del',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 80),
              ],
            ),

            // ------------------------------------------------
            // BOTTOM NAVIGATION
            // ------------------------------------------------

            bottomNavigationBar: BottomAppBar(
              height: 64,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Поиск босса',
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      go(context, const SearchScreen());
                    },
                  ),

                  IconButton(
                    tooltip: 'Отменить (${ctrl.undoCount}/$maxUndo)',
                    icon: Badge(
                      isLabelVisible: ctrl.undoCount > 0,
                      label: Text('${ctrl.undoCount}'),
                      child: const Icon(Icons.undo),
                    ),
                    onPressed: () {
                      if (!ctrl.undo()) {
                        toast(
                          context,
                          'История изменений пуста.',
                        );
                      }
                    },
                  ),

                  IconButton(
                    tooltip: 'Сохранить + backup',
                    icon: const Icon(Icons.save),
                    onPressed: () => doSave(context),
                  ),

                  const Spacer(),

                  Text(
                    ctrl.dirty ? 'Есть изменения' : 'Сохранено',
                    style: TextStyle(
                      fontSize: 11,
                      color: ctrl.dirty
                          ? Colors.amber
                          : Colors.grey,
                    ),
                  ),

                  const SizedBox(width: 12),
                ],
              ),
            ),

            // ------------------------------------------------
            // CREATE ZONE
            // ------------------------------------------------

            floatingActionButton: FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Зона'),
              onPressed: () async {
                final r = await form(
                  context,
                  'Создание зоны',
                  {
                    'Name': '',
                    'FileName': '',
                  },
                );

                if (r == null) return;

                if (r['Name']!.isEmpty ||
                    r['FileName']!.isEmpty) {
                  if (context.mounted) {
                    toast(
                      context,
                      'Значение не может быть пустым.',
                    );
                  }
                  return;
                }

                ctrl.createZone(
                  r['Name']!,
                  r['FileName']!,
                );
              },
            ),
          ),
        );
      },
    );
  }
}
