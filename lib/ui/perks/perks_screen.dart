import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../boss/attrs_screen.dart';
import '../common/dialogs.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';

class PerksScreen extends StatelessWidget {
  final XmlElement parent;

  final bool rule;

  final String title;

  const PerksScreen(
    this.parent, {
    required this.rule,
    required this.title,
    super.key,
  });

  Future<void> _preset(BuildContext context) async {
    final keys = presetPerks.keys.toList();

    final i = await pick(
      context,
      'PRESET PERKS',
      [
        for (final k in keys)
          '${presetPerks[k]!.$1}\n${presetPerks[k]!.$2}',
      ],
    );

    if (i != null) {
      ctrl.addPresetPerk(parent, keys[i]);
    }
  }

  Future<void> _custom(BuildContext context) async {
    final r = await form(
      context,
      rule ? 'Новый Rule-Perk' : 'Новый Perk',
      rule
          ? {'Name': '', 'ApplyTo': 'Player'}
          : {'Name': ''},
    );

    if (r == null || r['Name']!.isEmpty) return;

    if (!context.mounted) return;

    final addSet = await confirm(
      context,
      'Добавить <Set>?',
    );

    final apply = rule && r['ApplyTo']!.isNotEmpty
        ? r['ApplyTo']
        : null;

    ctrl.addCustomPerk(
      parent,
      r['Name']!,
      setAttrs: addSet ? {} : null,
      applyTo: apply,
    );
  }

  Future<void> _edit(
    BuildContext context,
    XmlElement p,
  ) async {
    final i = await pick(
      context,
      p.attr('Name', '?'),
      [
        rule ? 'Name / ApplyTo' : 'Name',
        'Set атрибуты',
        'Удалить',
      ],
    );

    if (i == null || !context.mounted) return;

    if (i == 0) {
      final r = await form(
        context,
        'Perk',
        rule
            ? {
                'Name': p.attr('Name'),
                'ApplyTo': p.attr('ApplyTo'),
              }
            : {
                'Name': p.attr('Name'),
              },
        hint: rule
            ? 'Пустой ApplyTo — удалить атрибут'
            : '',
      );

      if (r != null) {
        ctrl.editPerk(
          p,
          name: r['Name'],
          applyTo: rule ? r['ApplyTo'] : null,
        );
      }
    } else if (i == 1) {
      final set = ctrl.ensureSetNode(p);

      go(
        context,
        AttrsScreen(
          set,
          '${p.attr('Name', '?')} <Set>',
        ),
      );
    } else {
      if (await confirm(context, 'Удалить Perk?')) {
        ctrl.removeChild(p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!rule)
            IconButton(
              tooltip: 'Из пресета',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _preset(context),
            ),
          IconButton(
            tooltip: 'Кастомный',
            icon: const Icon(Icons.add),
            onPressed: () => _custom(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final items = parent.kids('Perk').toList();

          if (items.isEmpty) {
            return emptyNote('Perks отсутствуют.');
          }

          return ListView(
            children: [
              for (final p in items)
                ListTile(
                  title: Text(p.attr('Name', '?')),
                  subtitle: Text([
                    if (p.getAttribute('ApplyTo') != null)
                      'ApplyTo=${p.attr('ApplyTo')}',
                    if (p.kid('Set') != null)
                      p.kid('Set')!.attrMap.toString(),
                  ].join('   ')),
                  onTap: () => _edit(context, p),
                ),
            ],
          );
        },
      ),
    );
  }
}
