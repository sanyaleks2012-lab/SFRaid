import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../common/dialogs.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import '../perks/perks_screen.dart';
import 'complex_rules_screen.dart';
import 'conditions_screen.dart';
import 'equip_screen.dart';

class RulesScreen extends StatelessWidget {
  final XmlElement rules;

  const RulesScreen(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final avatar = rules.kid('Avatar');

        final cname = rules.kid('Name');

        return Scaffold(
          appBar: AppBar(
            title: const Text('RULES / PLAYER SETUP'),
          ),
          body: ListView(
            children: [
              tile(
                Icons.face,
                'Avatar / Name',
                sub:
                    'Avatar: ${avatar?.attr('Name') ?? '—'}   '
                    'Name: ${cname?.attr('Name') ?? '—'}',
                onTap: () async {
                  final r = await form(
                    context,
                    'Avatar / Character Name',
                    {
                      'Avatar Name': avatar?.attr('Name') ?? '',
                      'Character Name': cname?.attr('Name') ?? '',
                    },
                    hint: 'Пустое поле — удалить элемент',
                  );

                  if (r != null) {
                    ctrl.editAvatarName(
                      rules,
                      r['Avatar Name']!,
                      r['Character Name']!,
                    );
                  }
                },
              ),
              tile(
                Icons.checkroom,
                'Экипировка Player — EquipItem',
                sub: '${rules.kids('EquipItem').length}',
                onTap: () => go(
                  context,
                  EquipScreen(rules),
                ),
              ),
              tile(
                Icons.auto_awesome,
                'Rule-Perks',
                sub: '${rules.kids('Perk').length}',
                onTap: () => go(
                  context,
                  PerksScreen(
                    rules,
                    rule: true,
                    title: 'RULE-PERKS',
                  ),
                ),
              ),
              tile(
                Icons.rule,
                'ComplexRules',
                sub: '${rules.kids('ComplexRule').length}',
                onTap: () => go(
                  context,
                  ComplexRulesScreen(rules),
                ),
              ),
              tile(
                Icons.account_tree,
                'RulesWithConditions',
                sub: '${rules.kids('RulesWithConditions').length}',
                onTap: () => go(
                  context,
                  ConditionsScreen(rules),
                ),
              ),
              tile(
                Icons.delete_sweep,
                'Очистить ВСЕ пользовательские Rules',
                onTap: () async {
                  if (await confirm(
                    context,
                    'Будут удалены: Avatar, Name, EquipItem, Perk, '
                    'ComplexRule, RulesWithConditions. Продолжить?',
                  )) {
                    ctrl.clearUserRules(rules);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
