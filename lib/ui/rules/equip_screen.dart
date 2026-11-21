import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../common/dialogs.dart';
import '../common/widgets.dart';

class EquipScreen extends StatelessWidget {
  final XmlElement rules;

  const EquipScreen(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PLAYER EQUIPMENT'),
        actions: [
          IconButton(
            tooltip: 'Быстрый комплект',
            icon: const Icon(Icons.bolt),
            onPressed: () async {
              final r = await form(
                context,
                'Быстрый комплект Player',
                {
                  'Items': '',
                  'ApplyTo': 'Player',
                },
                hint: 'Предметы через пробел, например:\n'
                    'WEAPON_INDIA_24 BODY_WOMAN HELM_CROWN_OF_NIGHT '
                    'RANGED_IND21_KUNAI MAGIC_INDIA_24',
              );

              if (r != null) {
                ctrl.quickEquipment(
                  rules,
                  r['Items']!,
                  r['ApplyTo']!.isEmpty
                      ? 'Player'
                      : r['ApplyTo']!,
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Добавить',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final r = await form(
                context,
                'Добавить EquipItem',
                {
                  'Item Name': '',
                  'ApplyTo': 'Player',
                },
              );

              if (r == null || r['Item Name']!.isEmpty) {
                return;
              }

              ctrl.addEquipItem(
                rules,
                r['Item Name']!,
                r['ApplyTo']!.isEmpty
                    ? 'Player'
                    : r['ApplyTo']!,
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final items = rules.kids('EquipItem').toList();

          if (items.isEmpty) {
            return emptyNote('EquipItem отсутствуют.');
          }

          return ListView(
            children: [
              for (final it in items)
                ListTile(
                  title: Text(it.attr('Name', '?')),
                  subtitle: Text(
                    'ApplyTo=${it.attr('ApplyTo', '—')}',
                  ),
                  onTap: () async {
                    final r = await form(
                      context,
                      'EquipItem',
                      {
                        'Name': it.attr('Name'),
                        'ApplyTo': it.attr('ApplyTo', 'Player'),
                      },
                    );

                    if (r != null && r['Name']!.isNotEmpty) {
                      ctrl.editEquipItem(
                        it,
                        r['Name']!,
                        r['ApplyTo']!,
                      );
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ctrl.removeChild(it),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
