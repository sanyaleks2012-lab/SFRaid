import 'package:flutter/material.dart';
import '../app_state.dart';
import '../core/l10n.dart';
import '../core/perk_source.dart';
import '../core/raid_controller.dart';
import 'widgets.dart';

Future<void> showPerksSheet(
    BuildContext context, RaidForgeController ctrl, int battleIndex) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _PerksSheet(ctrl: ctrl, battleIndex: battleIndex),
  );
}

class _PerksSheet extends StatefulWidget {
  final RaidForgeController ctrl;
  final int battleIndex;
  const _PerksSheet({required this.ctrl, required this.battleIndex});

  @override
  State<_PerksSheet> createState() => _PerksSheetState();
}

class _PerksSheetState extends State<_PerksSheet> {
  String _q = '';

  String get _originLabel => switch (widget.ctrl.perkLoad.origin) {
        'enchant' => tr('perks.origin.enchant'),
        'perks' => tr('perks.origin.perks'),
        'merged' => tr('perks.origin.merged'),
        _ => tr('perks.origin.none'),
      };

  void _add(PerkDef def) {
    final battle = widget.ctrl.battleAt(widget.battleIndex);
    final w = battle == null ? null : widget.ctrl.warriorOf(battle);
    if (w == null) {
      snack(context, tr('toast.noWarrior'));
      return;
    }
    if (widget.ctrl.hasPerk(w, def.name)) {
      snack(context, tr('perks.exists'));
      return;
    }
    widget.ctrl.addPerk(w, def);
    snack(context, tr('perks.added', {'name': def.name}));
  }

  Future<void> _setMode(PerkMergeMode mode) async {
    await appState.setPerkMode(mode);
    await widget.ctrl.reloadPerks(mode);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final q = _q.trim().toLowerCase();
    final list = ctrl.perkDefs
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('perks.title'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                SegmentedButton<PerkMergeMode>(
                  segments: [
                    ButtonSegment(
                      value: PerkMergeMode.replace,
                      label: Text(tr('perks.mode.replace')),
                    ),
                    ButtonSegment(
                      value: PerkMergeMode.extend,
                      label: Text(tr('perks.mode.extend')),
                    ),
                  ],
                  selected: {appState.perkMode},
                  onSelectionChanged: (s) => _setMode(s.first),
                ),
                const SizedBox(height: 8),
                Text(_originLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: tr('perks.search'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(tr('perks.origin.none')))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final p = list[i];
                      final battle = ctrl.battleAt(widget.battleIndex);
                      final w = battle == null ? null : ctrl.warriorOf(battle);
                      final has = w != null && ctrl.hasPerk(w, p.name);
                      return ListTile(
                        leading: Icon(
                          has ? Icons.check_circle : Icons.bolt_outlined,
                          color: has ? Colors.greenAccent : null,
                        ),
                        title: Text(p.name),
                        subtitle: Text(
                          p.setSummary.isEmpty ? p.origin : p.setSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _add(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}