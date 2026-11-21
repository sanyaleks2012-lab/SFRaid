import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../common/dialogs.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';

class RewardsScreen extends StatelessWidget {
  final XmlElement battle;

  const RewardsScreen(this.battle, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('REWARDS / CURRENCY'),
        actions: [
          IconButton(
            tooltip: 'Создать Reward',
            icon: const Icon(Icons.add),
            onPressed: () {
              final r = ctrl.createReward(battle);

              go(
                context,
                RewardScreen(r),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final rewards = battle.kids('Reward').toList();

          if (rewards.isEmpty) {
            return emptyNote('Rewards нет.');
          }

          return ListView(
            children: [
              for (var i = 0; i < rewards.length; i++)
                ListTile(
                  title: Text('Reward ${i + 1}'),
                  subtitle: Text(
                    'PrizeBase=${rewards[i].attr('PrizeBase', '—')} '
                    'Exp=${rewards[i].attr('Exp', '—')} '
                    'Bonus=${rewards[i].attr('Bonus', '—')}\n'
                    '${rewards[i].kids('Currency').map(
                          (c) => '↳ ${c.attr('Name', '?')} = '
                              '${c.attr('ExpectedValue', '?')}',
                        ).join('\n')}',
                  ),
                  isThreeLine: true,
                  onTap: () => go(
                    context,
                    RewardScreen(rewards[i]),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить Reward?',
                      )) {
                        ctrl.removeChild(rewards[i]);
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class RewardScreen extends StatelessWidget {
  final XmlElement reward;

  const RewardScreen(this.reward, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('REWARD'),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить Currency',
        child: const Icon(Icons.add),
        onPressed: () async {
          final r = await form(
            context,
            'Добавить Currency',
            {
              'Currency Name': '',
              'ExpectedValue': '0',
            },
          );

          if (r == null || r['Currency Name']!.isEmpty) {
            return;
          }

          ctrl.addCurrency(
            reward,
            r['Currency Name']!,
            r['ExpectedValue']!.isEmpty
                ? '0'
                : r['ExpectedValue']!,
          );
        },
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final cs = reward.kids('Currency').toList();

          return ListView(
            children: [
              tile(
                Icons.edit,
                'PrizeBase / Exp / Bonus',
                sub:
                    'PrizeBase=${reward.attr('PrizeBase', '—')}  '
                    'Exp=${reward.attr('Exp', '—')}  '
                    'Bonus=${reward.attr('Bonus', '—')}',
                onTap: () async {
                  final r = await form(
                    context,
                    'Reward',
                    {
                      'PrizeBase': reward.attr('PrizeBase'),
                      'Exp': reward.attr('Exp'),
                      'Bonus': reward.attr('Bonus'),
                    },
                  );

                  if (r != null) {
                    ctrl.editReward(
                      reward,
                      prizeBase: r['PrizeBase']!,
                      exp: r['Exp']!,
                      bonus: r['Bonus']!,
                    );
                  }
                },
              ),
              const Divider(),
              if (cs.isEmpty)
                emptyNote('Currency нет.'),
              for (final c in cs)
                ListTile(
                  title: Text(c.attr('Name', '?')),
                  subtitle: Text(
                    'ExpectedValue=${c.attr('ExpectedValue', '?')}',
                  ),
                  onTap: () async {
                    final r = await form(
                      context,
                      'Currency',
                      {
                        'Name': c.attr('Name'),
                        'ExpectedValue': c.attr('ExpectedValue', '0'),
                      },
                    );

                    if (r != null) {
                      ctrl.editCurrency(
                        c,
                        r['Name']!,
                        r['ExpectedValue']!,
                      );
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ctrl.removeChild(c),
                  ),
                ),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}
