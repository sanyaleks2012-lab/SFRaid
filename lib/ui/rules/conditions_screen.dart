import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../boss/attrs_screen.dart';
import '../common/dialogs.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';

class ConditionsScreen extends StatelessWidget {
  final XmlElement rules;

  const ConditionsScreen(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RULES WITH CONDITIONS'),
        actions: [
          IconButton(
            tooltip: 'Создать',
            icon: const Icon(Icons.add),
            onPressed: () {
              ctrl.createRulesWithConditions(rules);
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final ws = rules.kids('RulesWithConditions').toList();

          if (ws.isEmpty) {
            return emptyNote('Блоков нет.');
          }

          return ListView(
            children: [
              for (var i = 0; i < ws.length; i++)
                ListTile(
                  title: Text('Блок ${i + 1}'),
                  subtitle: Text(
                    'Conditions=${ws[i].kid('Conditions')?.childElements.length ?? 0} '
                    'Rules=${ws[i].kid('RuleList')?.childElements.length ?? 0}',
                  ),
                  onTap: () {
                    ctrl.ensureConditions(ws[i]);
                    ctrl.ensureRuleList(ws[i]);

                    go(
                      context,
                      ConditionEditorScreen(ws[i]),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить RulesWithConditions?',
                      )) {
                        ctrl.removeChild(ws[i]);
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

class ConditionEditorScreen extends StatelessWidget {
  final XmlElement wrapper;

  const ConditionEditorScreen(this.wrapper, {super.key});

  List<Widget> _section(
    BuildContext context,
    String title,
    XmlElement? parent,
    String hintTag,
  ) {
    if (parent == null) return [];

    final items = parent.childElements.toList();

    return [
      ListTile(
        tileColor: Colors.white10,
        title: Text('$title (${items.length})'),
        trailing: IconButton(
          icon: const Icon(Icons.add),
          onPressed: () async {
            final r = await form(
              context,
              'Tag',
              {'Tag': hintTag},
            );

            if (r == null || r['Tag']!.isEmpty) {
              return;
            }

            final child = ctrl.addChild(
              parent,
              r['Tag']!,
            );

            if (context.mounted) {
              go(
                context,
                AttrsScreen(
                  child,
                  '$title / ${child.name.local}',
                ),
              );
            }
          },
        ),
      ),
      for (final it in items)
        ListTile(
          title: Text(it.name.local),
          subtitle: Text(it.attrMap.toString()),
          onTap: () => go(
            context,
            AttrsScreen(it, it.name.local),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => ctrl.removeChild(it),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONDITIONS'),
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          return ListView(
            children: [
              ..._section(
                context,
                'Conditions',
                wrapper.kid('Conditions'),
                'Equal',
              ),
              ..._section(
                context,
                'RuleList',
                wrapper.kid('RuleList'),
                'NoButton',
              ),
            ],
          );
        },
      ),
    );
  }
}
