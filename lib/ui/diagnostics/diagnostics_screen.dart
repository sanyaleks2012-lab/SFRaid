import 'package:flutter/material.dart';

import '../../core/session.dart';

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final d = ctrl.diagnostics();

    final s = d.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('XML DIAGNOSTICS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (d.errors.isEmpty)
            const Text(
              '✓ Критических структурных ошибок не обнаружено.',
              style: TextStyle(color: Colors.greenAccent),
            )
          else ...[
            Text(
              'Ошибки: ${d.errors.length}',
              style: const TextStyle(color: Colors.redAccent),
            ),
            for (final e in d.errors)
              Text('✗ $e'),
          ],
          if (d.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Предупреждения: ${d.warnings.length}',
              style: const TextStyle(color: Colors.amber),
            ),
            for (final w in d.warnings)
              Text('• $w'),
          ],
          const SizedBox(height: 16),
          const Text(
            'Statistics',
            style: TextStyle(color: Colors.cyanAccent),
          ),
          if (ctrl.kind.isQuests)
            Text(
              'Quests=${s.quests}, Dojo=${s.dojos}, Include=${s.includes}',
            )
          else ...[
            Text(
              'Zones=${s.zones}, Battles=${s.battles}, Warriors=${s.warriors}',
            ),
            Text(
              'WarriorPerks=${s.warriorPerks}, '
              'RulePerks=${s.rulePerks}, '
              'ComplexRules=${s.complexRules}',
            ),
            Text(
              'EquipItems=${s.equipItems}, '
              'Currency=${s.currencies}, '
              'Conditions=${s.conditions}',
            ),
          ],
        ],
      ),
    );
  }
}
