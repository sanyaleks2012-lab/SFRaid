import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../boss/attrs_screen.dart';
import '../common/dialogs.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';

class ComplexRulesScreen extends StatelessWidget {
  final XmlElement rules;

  const ComplexRulesScreen(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('COMPLEX RULES'),
        actions: [
          IconButton(
            tooltip: 'Добавить из пресета',
            icon: const Icon(Icons.playlist_add),
            onPressed: () async {
              final keys = presetRules.keys.toList();

              final i = await pick(
                context,
                'COMPLEX RULE PRESETS',
                [
                  for (final k in keys)
                    '${presetRules[k]!.$1} → ${presetRules[k]!.$3}',
                ],
              );

              if (i != null) {
                ctrl.addComplexRulePreset(
                  rules,
                  keys[i],
                );
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final list = rules.kids('ComplexRule').toList();

          if (list.isEmpty) {
            return emptyNote('ComplexRule нет.');
          }

          return ListView(
            children: [
              for (final r in list)
                ListTile(
                  title: Text(
                    r.kid('Description')?.attr('Alias', '?') ?? '?',
                  ),
                  subtitle: Text(
                    ctrl.complexRuleChildren(r)
                        .map((e) => e.name.local)
                        .join(', '),
                  ),
                  onTap: () => go(
                    context,
                    ComplexRuleScreen(r),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить ComplexRule?',
                      )) {
                        ctrl.removeChild(r);
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

class ComplexRuleScreen extends StatelessWidget {
  final XmlElement rule;

  const ComplexRuleScreen(this.rule, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('COMPLEX RULE'),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить дочерний XML-узел',
        child: const Icon(Icons.add),
        onPressed: () async {
          final r = await form(
            context,
            'Добавить дочерний узел',
            {'Имя XML-узла': ''},
          );

          if (r == null || r['Имя XML-узла']!.isEmpty) {
            return;
          }

          final child = ctrl.addChild(
            rule,
            r['Имя XML-узла']!,
          );

          if (context.mounted) {
            go(
              context,
              AttrsScreen(child, child.name.local),
            );
          }
        },
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final children = ctrl.complexRuleChildren(rule);

          return ListView(
            children: [
              tile(
                Icons.label,
                'Alias',
                sub: rule.kid('Description')?.attr('Alias', '') ?? '',
                onTap: () async {
                  final r = await form(
                    context,
                    'Alias',
                    {
                      'Alias': rule.kid('Description')
                              ?.attr('Alias', '') ??
                          '',
                    },
                  );

                  if (r != null) {
                    ctrl.setComplexRuleAlias(
                      rule,
                      r['Alias']!,
                    );
                  }
                },
              ),
              const Divider(),
              if (children.isEmpty)
                emptyNote('Дочерних узлов нет.'),
              for (final ch in children)
                ListTile(
                  title: Text(ch.name.local),
                  subtitle: Text(ch.attrMap.toString()),
                  onTap: () => go(
                    context,
                    AttrsScreen(ch, ch.name.local),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить ${ch.name.local}?',
                      )) {
                        ctrl.removeChild(ch);
                      }
                    },
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
