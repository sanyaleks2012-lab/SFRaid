import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../boss/boss_screen.dart';
import '../common/dialogs.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';

class ZoneScreen extends StatelessWidget {
  final XmlElement zone;

  const ZoneScreen(this.zone, {super.key});

  Future<void> _cloneToZone(BuildContext context) async {
    final all = ctrl.battles();

    if (all.isEmpty) {
      toast(context, 'Нет боёв для клонирования.');
      return;
    }

    final i = await pick(
      context,
      'Шаблон босса',
      [
        for (final (z, b) in all)
          '[${z.attr('Name', '?')}] ${b.attr('Name', '?')}',
      ],
    );

    if (i == null || !context.mounted) return;

    final cur = all[i].$2.attr('Name', 'BOSS');

    final r = await form(
      context,
      'Новое Name',
      {'Name': '${cur}_COPY'},
    );

    if (r == null) return;

    ctrl.cloneBattleToZone(
      all[i].$2,
      zone,
      r['Name'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final battles = zone.kids('Battle').toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('ЗОНА — ${zone.attr('Name', '?')}'),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.content_copy),
            label: const Text('Клонировать босса'),
            onPressed: () => _cloneToZone(context),
          ),
          body: battles.isEmpty
              ? emptyNote('Боёв нет.')
              : ListView(
                  children: [
                    for (final b in battles)
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(b.attr('Name', 'UNKNOWN')),
                        subtitle: Text(
                          '${b.attr('Title', 'N/A')} • '
                          'PWR=${ctrl.getWarrior(b)?.attr('WarriorPower', '?') ?? '?'}',
                        ),
                        onTap: () => go(
                          context,
                          BossScreen(b),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'dup') {
                              final r = await form(
                                context,
                                'Дублировать бой',
                                {
                                  'Name':
                                      '${b.attr('Name', 'BOSS')}_COPY',
                                },
                              );

                              if (r != null) {
                                ctrl.duplicateBattle(
                                  zone,
                                  b,
                                  r['Name'],
                                );
                              }
                            } else if (v == 'del') {
                              if (await confirm(
                                context,
                                'Удалить ${b.attr('Name')}?',
                              )) {
                                ctrl.deleteBattle(b);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'dup',
                              child: Text('Дублировать в этой зоне'),
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
        );
      },
    );
  }
}
