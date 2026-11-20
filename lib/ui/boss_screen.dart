import 'package:flutter/material.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../core/xml_utils.dart';
import 'perks_sheet.dart';
import 'widgets.dart';
import 'package:xml/xml.dart';

class BossScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  final int index;

  const BossScreen({super.key, required this.ctrl, required this.index});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final b = ctrl.battleAt(index);
        if (b == null) {
          return Scaffold(body: Center(child: Text(tr('common.none'))));
        }
        final w = ctrl.warriorOf(b);
        final f = ctrl.fightOf(b);
        final rules = f == null ? null : ctrl.rulesOf(b);
        final reward = ctrl.rewardOf(b);
        final name = b.attr('Name', '?');

        return Scaffold(
          appBar: AppBar(title: Text(tr('boss.title', {'name': name}))),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              SectionCard(
                title: tr('boss.identity'),
                icon: Icons.badge_outlined,
                onEdit: () => _editIdentity(context, b),
                children: [
                  InfoRow(tr('sheet.name'), name),
                  InfoRow(tr('sheet.title'), b.attr('Title', tr('common.none'))),
                  InfoRow(tr('boss.location'), b.attr('Location', tr('common.none'))),
                ],
              ),
              SectionCard(
                title: tr('boss.warrior'),
                icon: Icons.person_outline,
                onEdit: w == null ? null : () => _editWarrior(context, w),
                children: w == null
                    ? [ListTile(title: Text(tr('boss.noWarrior')))]
                    : [
                        InfoRow(tr('sheet.template'), w.attr('Template', tr('common.none'))),
                        InfoRow(tr('boss.power'),
                            '${w.attr('WarriorPower', '0')} / ${w.attr('ShieldTotal', '0')}'),
                      ],
              ),
              SectionCard(
                title: tr('boss.fight'),
                icon: Icons.timer_outlined,
                onEdit: f == null ? null : () => _editRounds(context, f),
                children: f == null
                    ? [ListTile(title: Text(tr('boss.noFight')))]
                    : [
                        InfoRow(tr('sheet.rounds'), f.attr('Rounds', '—')),
                        InfoRow(tr('sheet.roundTime'), f.attr('RoundTime', '—')),
                      ],
              ),
              SectionCard(
                title: tr('boss.perks'),
                icon: Icons.auto_awesome_outlined,
                action: w == null
                    ? null
                    : IconButton(
                        tooltip: tr('boss.addPerk'),
                        icon: const Icon(Icons.add),
                        onPressed: () => showPerksSheet(context, ctrl, index),
                      ),
                children: _perkTiles(context, w),
              ),
              SectionCard(
                title: tr('boss.rules'),
                icon: Icons.checkroom_outlined,
                action: f == null
                    ? null
                    : IconButton(
                        tooltip: tr('boss.addItem'),
                        icon: const Icon(Icons.add),
                        onPressed: () => _addItem(context, f),
                      ),
                children: _itemTiles(context, rules),
              ),
              SectionCard(
                title: tr('boss.rewards'),
                icon: Icons.card_giftcard_outlined,
                onEdit: () => _editReward(context, b, reward),
                children: reward == null
                    ? [ListTile(title: Text(tr('boss.noReward')))]
                    : [
                        InfoRow(tr('sheet.prizeBase'), reward.attr('PrizeBase', '—')),
                        InfoRow(tr('sheet.exp'), reward.attr('Exp', '—')),
                        InfoRow(tr('sheet.bonus'), reward.attr('Bonus', '—')),
                      ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _perkTiles(BuildContext context, XmlElement? w) {
    if (w == null) return [ListTile(title: Text(tr('boss.noWarrior')))];
    final perks = w.kid('Perks')?.kids('Perk').toList() ?? [];
    if (perks.isEmpty) return [ListTile(title: Text(tr('boss.noPerks')))];
    return [
      for (final p in perks)
        ListTile(
          dense: true,
          leading: const Icon(Icons.bolt, size: 18),
          title: Text(p.attr('Name', '?')),
          subtitle: p.kid('Set') == null
              ? null
              : Text(p.kid('Set')!.attributes
                  .map((a) => '${a.name.local}=${a.value}')
                  .join('  ')),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => ctrl.removeNode(p),
          ),
        ),
    ];
  }

  List<Widget> _itemTiles(BuildContext context, XmlElement? rules) {
    final items = rules?.kids('EquipItem').toList() ?? [];
    if (items.isEmpty) return [ListTile(title: Text(tr('boss.noItems')))];
    return [
      for (final it in items)
        ListTile(
          dense: true,
          title: Text(it.attr('Name', '?')),
          subtitle: Text('${tr('sheet.applyTo')}=${it.attr('ApplyTo', '—')}'),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => ctrl.removeNode(it),
          ),
        ),
    ];
  }

  Future<void> _editIdentity(BuildContext context, XmlElement b) async {
    final r = await showFieldsSheet(context, tr('boss.identity'), [
      FieldSpec('name', tr('sheet.name'), b.attr('Name')),
      FieldSpec('title', tr('sheet.title'), b.attr('Title')),
      FieldSpec('loc', tr('sheet.location'), b.attr('Location')),
    ]);
    if (r == null || !context.mounted) return;
    guard(context, () {
      ctrl.renameBattle(b, r['name']!, r['title']!);
      ctrl.setAttr(b, 'Location', r['loc']!);
    });
  }

  Future<void> _editWarrior(BuildContext context, XmlElement w) async {
    final r = await showFieldsSheet(context, tr('boss.power'), [
      FieldSpec('power', tr('sheet.power'), w.attr('WarriorPower', '0'), numeric: true),
      FieldSpec('shields', tr('sheet.shields'), w.attr('ShieldTotal', '0'), numeric: true),
    ]);
    if (r == null) return;
    ctrl.setWarriorStats(w, power: r['power']!, shields: r['shields']!);
  }

  Future<void> _editRounds(BuildContext context, XmlElement f) async {
    final r = await showFieldsSheet(context, tr('boss.fight'), [
      FieldSpec('rounds', tr('sheet.rounds'), f.attr('Rounds', '0'), numeric: true),
      FieldSpec('time', tr('sheet.roundTime'), f.attr('RoundTime', '999'), numeric: true),
    ]);
    if (r == null) return;
    ctrl.setRounds(f, rounds: r['rounds']!, roundTime: r['time']!);
  }

  Future<void> _editReward(BuildContext context, XmlElement b, XmlElement? reward) async {
    final r = await showFieldsSheet(context, tr('boss.rewards'), [
      FieldSpec('prize', tr('sheet.prizeBase'), reward?.attr('PrizeBase', '0') ?? '0', numeric: true),
      FieldSpec('exp', tr('sheet.exp'), reward?.attr('Exp', '0') ?? '0', numeric: true),
      FieldSpec('bonus', tr('sheet.bonus'), reward?.attr('Bonus', '0') ?? '0', numeric: true),
    ]);
    if (r == null) return;
    ctrl.setReward(b, prize: r['prize']!, exp: r['exp']!, bonus: r['bonus']!);
  }

  Future<void> _addItem(BuildContext context, XmlElement fight) async {
    final r = await showFieldsSheet(context, tr('boss.addItem'), [
      FieldSpec('name', tr('sheet.item'), ''),
      FieldSpec('apply', tr('sheet.applyTo'), 'Player'),
    ]);
    if (r == null || r['name']!.isEmpty) return;
    final rules = ctrl.ensureRules(fight);
    ctrl.addEquip(rules, r['name']!, r['apply']!.isEmpty ? 'Player' : r['apply']!);
  }
}