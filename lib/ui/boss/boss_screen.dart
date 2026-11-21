import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../common/dialogs.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import '../perks/perks_screen.dart';
import '../rewards/rewards_screen.dart';
import '../rules/rules_screen.dart';
import '../xml/xml_view_screen.dart';
import 'attrs_screen.dart';

class BossScreen extends StatelessWidget {
  final XmlElement battle;

  const BossScreen(this.battle, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final warrior = ctrl.getWarrior(battle);

        final fight = ctrl.getFight(battle);

        final name = battle.attr('Name', 'N/A');

        return Scaffold(
          appBar: AppBar(
            title: Text('БОСС — $name'),
          ),
          body: ListView(
            children: [
              tile(
                Icons.edit,
                'Имя / Title',
                sub: '$name / ${battle.attr('Title', 'N/A')}',
                onTap: () async {
                  final r = await form(
                    context,
                    'Имя / Title',
                    {
                      'Name': battle.attr('Name'),
                      'Title': battle.attr('Title'),
                    },
                  );

                  if (r != null) {
                    ctrl.editBossIdentity(
                      battle,
                      r['Name']!,
                      r['Title']!,
                    );
                  }
                },
              ),
              tile(
                Icons.place,
                'Location',
                sub: battle.attr('Location', 'N/A'),
                onTap: () async {
                  final r = await form(
                    context,
                    'Location',
                    {
                      'Location': battle.attr('Location'),
                    },
                  );

                  if (r != null) {
                    ctrl.changeAttr(
                      battle,
                      'Location',
                      r['Location']!,
                    );
                  }
                },
              ),
              tile(
                Icons.tune,
                'Battle attributes',
                sub: '${battle.attributes.length} attrs',
                onTap: () => go(
                  context,
                  AttrsScreen(battle, 'Battle attributes'),
                ),
              ),
              tile(
                Icons.person_outline,
                'Warrior Template',
                sub: warrior?.attr('Template', 'N/A') ?? 'N/A',
                onTap: () async {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  final r = await form(
                    context,
                    'Template',
                    {
                      'Template': warrior.attr('Template'),
                    },
                  );

                  if (r != null) {
                    ctrl.changeAttr(
                      warrior,
                      'Template',
                      r['Template']!,
                    );
                  }
                },
              ),
              tile(
                Icons.shield,
                'Warrior Power / Shields',
                sub:
                    '${warrior?.attr('WarriorPower', 'N/A') ?? 'N/A'} / '
                    '${warrior?.attr('ShieldTotal', '0') ?? '0'}',
                onTap: () async {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  final r = await form(
                    context,
                    'Power / Shields',
                    {
                      'WarriorPower':
                          warrior.attr('WarriorPower', '0'),
                      'ShieldTotal':
                          warrior.attr('ShieldTotal', '0'),
                    },
                  );

                  if (r != null) {
                    ctrl.editPowerShields(
                      warrior,
                      r['WarriorPower']!,
                      r['ShieldTotal']!,
                    );
                  }
                },
              ),
              tile(
                Icons.timer,
                'Rounds / RoundTime',
                sub:
                    '${fight?.attr('Rounds', 'N/A') ?? 'N/A'} / '
                    '${fight?.attr('RoundTime', 'N/A') ?? 'N/A'}s',
                onTap: () async {
                  if (fight == null) {
                    toast(context, 'Нет Fight');
                    return;
                  }

                  final r = await form(
                    context,
                    'Rounds / RoundTime',
                    {
                      'Rounds': fight.attr('Rounds', '0'),
                      'RoundTime': fight.attr('RoundTime', '999'),
                    },
                  );

                  if (r != null) {
                    ctrl.editRounds(
                      fight,
                      r['Rounds']!,
                      r['RoundTime']!,
                    );
                  }
                },
              ),
              tile(
                Icons.auto_awesome,
                'Warrior Perks',
                onTap: () {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  final perks = ctrl.ensurePerks(warrior);

                  go(
                    context,
                    PerksScreen(
                      perks,
                      rule: false,
                      title: 'WARRIOR PERKS',
                    ),
                  );
                },
              ),
              tile(
                Icons.rule,
                'Rules / Player Setup',
                onTap: () {
                  final rules = ctrl.ensureRules(battle);

                  if (rules == null) {
                    toast(context, 'Fight отсутствует.');
                    return;
                  }

                  go(context, RulesScreen(rules));
                },
              ),
              tile(
                Icons.card_giftcard,
                'Rewards / Currency',
                onTap: () => go(
                  context,
                  RewardsScreen(battle),
                ),
              ),
              tile(
                Icons.tune,
                'Warrior attributes',
                onTap: () {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  go(
                    context,
                    AttrsScreen(warrior, 'Warrior attributes'),
                  );
                },
              ),
              tile(
                Icons.code,
                'Полный XML Battle',
                onTap: () => go(
                  context,
                  XmlViewScreen(battle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
