import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import '../app_state.dart';
import '../core/l10n.dart';
import '../core/perk_source.dart';
import '../core/raid_controller.dart';
import '../core/xml_utils.dart';
import 'quests_screens.dart';
import 'widgets.dart';

String _setSummary(XmlElement perk) {
  final set = perk.kid('Set');
  if (set == null) return '';
  return set.attributes.map((a) => '${a.name.local}=${a.value}').join('  ');
}

class PerksScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  final int battleIndex;
  const PerksScreen({super.key, required this.ctrl, required this.battleIndex});

  XmlElement? _warrior() {
    final b = ctrl.battleAt(battleIndex);
    return b == null ? null : ctrl.warriorOf(b);
  }

  Future<void> _fromSource(BuildContext context) async {
    final w = _warrior();
    if (w == null) {
      snack(context, tr('toast.noWarrior'));
      return;
    }
    final defs = ctrl.perkDefs;
    if (defs.isEmpty) {
      snack(context, tr('err.noPerkFile'));
      return;
    }
    final i = await pick(context, tr('perks.title'), [
      for (final p in defs) '${p.name}   [${p.origin}]',
    ]);
    if (i == null || !context.mounted) return;
    final def = defs[i];
    if (ctrl.hasPerk(w, def.name)) {
      snack(context, tr('perks.exists'));
      return;
    }
    ctrl.addPerk(w, def);
    snack(context, tr('perks.added', {'name': def.name}));
  }

  Future<void> _custom(BuildContext context) async {
    final w = _warrior();
    if (w == null) {
      snack(context, tr('toast.noWarrior'));
      return;
    }
    final r = await showFieldsSheet(context, tr('perks.custom'), [
      FieldSpec('name', tr('sheet.name'), ''),
    ]);
    if (r == null || r['name']!.isEmpty || !context.mounted) return;
    ctrl.addPerkByName(w, r['name']!);
  }

  Future<void> _edit(BuildContext context, XmlElement p) async {
    final i = await pick(context, p.attr('Name', '?'), [
      tr('perks.rename'),
      tr('perks.setAttrs'),
      tr('common.delete'),
    ]);
    if (i == null || !context.mounted) return;
    if (i == 0) {
      final r = await showFieldsSheet(context, tr('perks.rename'), [
        FieldSpec('name', tr('sheet.name'), p.attr('Name')),
      ]);
      if (r == null || !context.mounted) return;
      guard(context, () {
        if (r['name']!.isEmpty) throw RaidForgeException('err.nameEmpty');
        ctrl.setAttr(p, 'Name', r['name']!);
      });
    } else if (i == 1) {
      final set = ctrl.ensureSetNode(p);
      goTo(context, AttrsScreen(
          ctrl: ctrl, el: set, title: '${p.attr('Name', '?')} <Set>'));
    } else {
      ctrl.removeNode(p);
    }
  }

  Future<void> _toggleMode() async {
    final next = appState.perkMode == PerkMergeMode.extend
        ? PerkMergeMode.replace
        : PerkMergeMode.extend;
    await appState.setPerkMode(next);
    await ctrl.reloadPerks(next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, appState]),
      builder: (context, _) {
        final w = _warrior();
        final perks = w?.kid('Perks')?.kids('Perk').toList() ?? <XmlElement>[];
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('boss.perks')),
            actions: [
              IconButton(
                tooltip: appState.perkMode == PerkMergeMode.extend
                    ? tr('perks.mode.extend')
                    : tr('perks.mode.replace'),
                icon: const Icon(Icons.merge_type),
                onPressed: _toggleMode,
              ),
            ],
          ),
          floatingActionButton: w == null
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'perkCustom',
                      tooltip: tr('perks.custom'),
                      onPressed: () => _custom(context),
                      child: const Icon(Icons.edit),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'perkSource',
                      icon: const Icon(Icons.add),
                      label: Text(tr('perks.fromSource')),
                      onPressed: () => _fromSource(context),
                    ),
                  ],
                ),
          body: w == null
              ? emptyNote(tr('boss.noWarrior'))
              : perks.isEmpty
                  ? emptyNote(tr('boss.noPerks'))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 150),
                      children: [
                        for (final p in perks)
                          ListTile(
                            leading: const Icon(Icons.bolt, size: 18),
                            title: Text(p.attr('Name', '?')),
                            subtitle: Text(_setSummary(p)),
                            onTap: () => _edit(context, p),
                          ),
                      ],
                    ),
        );
      },
    );
  }
}