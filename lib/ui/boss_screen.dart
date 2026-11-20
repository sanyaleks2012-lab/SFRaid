import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../core/xml_utils.dart';
import 'perks_screen.dart';
import 'quests_screens.dart';
import 'widgets.dart';

ListTile _tile(IconData icon, String title,
    {String? sub, VoidCallback? onTap}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: sub == null ? null : Text(sub),
    trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

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
          return Scaffold(appBar: AppBar(), body: emptyNote(tr('common.none')));
        }
        final w = ctrl.warriorOf(b);
        final f = ctrl.fightOf(b);
        final reward = ctrl.rewardOf(b);
        final name = b.attr('Name', '?');
        final none = tr('common.none');

        return Scaffold(
          appBar: AppBar(title: Text(tr('boss.title', {'name': name}))),
          body: ListView(
            children: [
              _tile(Icons.edit, '${tr('sheet.name')} / ${tr('sheet.title')}',
                  sub: '$name / ${b.attr('Title', none)}',
                  onTap: () => _identity(context, b)),
              _tile(Icons.place, tr('boss.location'),
                  sub: b.attr('Location', none),
                  onTap: () => _editAttrs(context, tr('boss.location'), b, [
                        ('Location', tr('sheet.location'), false),
                      ])),
              _tile(Icons.tune, tr('boss.battleAttrs'),
                  sub: '${b.attributes.length}',
                  onTap: () => goTo(
                      context,
                      AttrsScreen(
                          ctrl: ctrl, el: b, title: tr('boss.battleAttrs')))),
              _tile(Icons.person_outline, tr('boss.warrior'),
                  sub: w == null ? tr('boss.noWarrior') : w.attr('Template', none),
                  onTap: w == null
                      ? () => snack(context, tr('toast.noWarrior'))
                      : () => _editAttrs(context, tr('sheet.template'), w, [
                            ('Template', tr('sheet.template'), false),
                          ])),
              _tile(Icons.shield, tr('boss.power'),
                  sub: w == null
                      ? none
                      : '${w.attr('WarriorPower', '0')} / ${w.attr('ShieldTotal', '0')}',
                  onTap: w == null
                      ? () => snack(context, tr('toast.noWarrior'))
                      : () => _editAttrs(context, tr('boss.power'), w, [
                            ('WarriorPower', tr('sheet.power'), true),
                            ('ShieldTotal', tr('sheet.shields'), true),
                          ])),
              _tile(Icons.timer, tr('boss.fight'),
                  sub: f == null
                      ? none
                      : '${f.attr('Rounds', '—')} / ${f.attr('RoundTime', '—')}s',
                  onTap: f == null
                      ? () => snack(context, tr('toast.noFight'))
                      : () => _editAttrs(context, tr('boss.fight'), f, [
                            ('Rounds', tr('sheet.rounds'), true),
                            ('RoundTime', tr('sheet.roundTime'), true),
                          ])),
              _tile(Icons.auto_awesome, tr('boss.perks'),
                  sub: '${w?.kid('Perks')?.kids('Perk').length ?? 0}',
                  onTap: w == null
                      ? () => snack(context, tr('toast.noWarrior'))
                      : () => goTo(context,
                          PerksScreen(ctrl: ctrl, battleIndex: index))),
              _tile(Icons.checkroom, tr('boss.rules'),
                  sub: '${ctrl.rulesOf(b)?.kids('EquipItem').length ?? 0}',
                  onTap: () => goTo(context,
                      RulesScreen(ctrl: ctrl, battleIndex: index))),
              _tile(Icons.card_giftcard, tr('boss.rewards'),
                  sub: reward == null
                      ? tr('boss.noReward')
                      : 'PrizeBase=${reward.attr('PrizeBase', '—')}',
                  onTap: () => goTo(context,
                      RewardsScreen(ctrl: ctrl, battleIndex: index))),
              _tile(Icons.tune, tr('boss.warriorAttrs'),
                  onTap: w == null
                      ? () => snack(context, tr('toast.noWarrior'))
                      : () => goTo(
                          context,
                          AttrsScreen(
                              ctrl: ctrl,
                              el: w,
                              title: tr('boss.warriorAttrs')))),
              _tile(Icons.code, tr('boss.xml'),
                  onTap: () => goTo(context,
                      XmlScreen(ctrl: ctrl, el: b, editable: false))),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Future<void> _identity(BuildContext context, XmlElement b) async {
    final r = await showFieldsSheet(context, tr('boss.identity'), [
      FieldSpec('name', tr('sheet.name'), b.attr('Name')),
      FieldSpec('title', tr('sheet.title'), b.attr('Title')),
    ]);
    if (r == null || !context.mounted) return;
    guard(context, () => ctrl.renameBattle(b, r['name']!, r['title']!));
  }

  /// Универсальный диалог: список (attr, label, numeric) → setAttr для каждого.
  Future<void> _editAttrs(
    BuildContext context,
    String title,
    XmlElement el,
    List<(String, String, bool)> keys,
  ) async {
    final r = await showFieldsSheet(context, title, [
      for (final (attr, label, numeric) in keys)
        FieldSpec(attr, label, el.attr(attr), numeric: numeric),
    ]);
    if (r == null || !context.mounted) return;
        guard(context, () {
      for (final k in keys) {
        ctrl.setAttr(el, k.$1, r[k.$1]!);
      }
    });
  }
}

class RulesScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  final int battleIndex;
  const RulesScreen({super.key, required this.ctrl, required this.battleIndex});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final b = ctrl.battleAt(battleIndex);
        final f = b == null ? null : ctrl.fightOf(b);
        final rules = b == null ? null : ctrl.rulesOf(b);
        final avatar = rules?.kid('Avatar')?.attr('Name') ?? '';
        final cname = rules?.kid('Name')?.attr('Name') ?? '';
        final items = rules?.kids('EquipItem').toList() ?? <XmlElement>[];
        final none = tr('common.none');

        if (f == null) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('boss.rules'))),
            body: emptyNote(tr('boss.noFight')),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(tr('boss.rules'))),
          floatingActionButton: FloatingActionButton(
            tooltip: tr('boss.addItem'),
            child: const Icon(Icons.add),
            onPressed: () => _addItem(context, f),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _tile(Icons.face, tr('rules.avatarName'),
                  sub: 'Avatar: ${avatar.isEmpty ? none : avatar}   '
                      'Name: ${cname.isEmpty ? none : cname}',
                  onTap: () => _avatar(context, f, rules, avatar, cname)),
              const Divider(),
              if (items.isEmpty) emptyNote(tr('boss.noItems')),
              for (final it in items)
                ListTile(
                  title: Text(it.attr('Name', '?')),
                  subtitle: Text('${tr('sheet.applyTo')}=${it.attr('ApplyTo', none)}'),
                  onTap: () => _editItem(context, it),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ctrl.removeNode(it),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _avatar(BuildContext context, XmlElement fight,
      XmlElement? rules, String avatar, String cname) async {
    final r = await showFieldsSheet(context, tr('rules.avatarName'), [
      FieldSpec('avatar', tr('sheet.avatar'), avatar),
      FieldSpec('char', tr('sheet.character'), cname),
    ], hint: tr('dojo.hintEmptyRemoves'));
    if (r == null || !context.mounted) return;
    guard(context,
        () => ctrl.setAvatarName(rules ?? ctrl.ensureRules(fight), r['avatar']!, r['char']!));
  }

  Future<void> _addItem(BuildContext context, XmlElement fight) async {
    final r = await showFieldsSheet(context, tr('boss.addItem'), [
      FieldSpec('name', tr('sheet.item'), ''),
      FieldSpec('apply', tr('sheet.applyTo'), 'Player'),
    ]);
    if (r == null || r['name']!.isEmpty || !context.mounted) return;
    ctrl.addEquip(ctrl.ensureRules(fight), r['name']!,
        r['apply']!.isEmpty ? 'Player' : r['apply']!);
  }

  Future<void> _editItem(BuildContext context, XmlElement it) async {
    final r = await showFieldsSheet(context, tr('sheet.item'), [
      FieldSpec('name', tr('sheet.item'), it.attr('Name')),
      FieldSpec('apply', tr('sheet.applyTo'), it.attr('ApplyTo', 'Player')),
    ]);
    if (r == null || !context.mounted) return;
    guard(context, () => ctrl.editEquip(it, r['name']!, r['apply']!));
  }
}

class RewardsScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  final int battleIndex;
  const RewardsScreen({super.key, required this.ctrl, required this.battleIndex});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final b = ctrl.battleAt(battleIndex);
        if (b == null) {
          return Scaffold(appBar: AppBar(), body: emptyNote(tr('common.none')));
        }
        final reward = ctrl.rewardOf(b);
        final currencies = reward?.kids('Currency').toList() ?? <XmlElement>[];
        final none = tr('common.none');

        return Scaffold(
          appBar: AppBar(title: Text(tr('boss.rewards'))),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(tr('rewards.addCurrency')),
            onPressed: () => _addCurrency(context, b),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _tile(Icons.card_giftcard, tr('rewards.reward'),
                  sub: reward == null
                      ? tr('boss.noReward')
                      : 'PrizeBase=${reward.attr('PrizeBase', '—')}  '
                          'Exp=${reward.attr('Exp', '—')}  '
                          'Bonus=${reward.attr('Bonus', '—')}',
                  onTap: () => _editReward(context, b)),
              const Divider(),
              if (currencies.isEmpty) emptyNote(tr('boss.noReward')),
              for (final c in currencies)
                ListTile(
                  leading: const Icon(Icons.paid_outlined),
                  title: Text(c.attr('Name', '?')),
                  subtitle: Text('${tr('sheet.expected')}=${c.attr('ExpectedValue', none)}'),
                  onTap: () => _editCurrency(context, c),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ctrl.removeNode(c),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editReward(BuildContext context, XmlElement b) async {
    final r0 = ctrl.ensureReward(b);
    final r = await showFieldsSheet(context, tr('rewards.edit'), [
      FieldSpec('prize', tr('sheet.prizeBase'), r0.attr('PrizeBase', '0'), numeric: true),
      FieldSpec('exp', tr('sheet.exp'), r0.attr('Exp', '0'), numeric: true),
      FieldSpec('bonus', tr('sheet.bonus'), r0.attr('Bonus', '0'), numeric: true),
    ]);
    if (r == null || !context.mounted) return;
    guard(context,
        () => ctrl.setReward(b, prize: r['prize']!, exp: r['exp']!, bonus: r['bonus']!));
  }

  Future<void> _addCurrency(BuildContext context, XmlElement b) async {
    final r = await showFieldsSheet(context, tr('rewards.addCurrency'), [
      FieldSpec('name', tr('sheet.name'), ''),
      FieldSpec('value', tr('sheet.expected'), '0', numeric: true),
    ]);
    if (r == null || r['name']!.isEmpty || !context.mounted) return;
    ctrl.addCurrency(ctrl.ensureReward(b), r['name']!,
        r['value']!.isEmpty ? '0' : r['value']!);
  }

  Future<void> _editCurrency(BuildContext context, XmlElement c) async {
    final r = await showFieldsSheet(context, tr('rewards.editCurrency'), [
      FieldSpec('name', tr('sheet.name'), c.attr('Name')),
      FieldSpec('value', tr('sheet.expected'), c.attr('ExpectedValue', '0'), numeric: true),
    ]);
    if (r == null || !context.mounted) return;
    guard(context, () => ctrl.editCurrency(c, r['name']!, r['value']!));
  }
}