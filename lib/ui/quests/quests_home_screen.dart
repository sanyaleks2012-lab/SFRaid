import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../common/dialogs.dart';
import '../common/editor_bottom_bar.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import '../diagnostics/diagnostics_screen.dart';
import 'dojo_changer_screen.dart';
import 'quest_list_screen.dart';

class QuestsHomeScreen extends StatelessWidget {
  const QuestsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final st = ctrl.statistics();
        final diag = ctrl.diagnostics();

        return PopScope(
          canPop: !ctrl.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;

            final ok = await confirm(
              context,
              'Есть несохранённые изменения. Выйти без сохранения?',
            );

            if (ok && context.mounted) Navigator.of(context).pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                ctrl.dirty ? 'QUESTS  ● изменён' : 'QUESTS',
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'diag') {
                      go(context, const DiagnosticsScreen());
                    }

                    if (v == 'about') {
                      showAboutDialog(
                        context: context,
                        applicationName: 'SF2 Raid Forge — Quests',
                        children: const [
                          Text(
                            'Редактор quests.xml.\n\n'
                            'Выбор додзё (Dojo Changer): страницы, '
                            'SELECT-загрузка, стартовое восстановление. '
                            'Все квесты: поиск, правка атрибутов и XML, '
                            'дублирование, удаление. Undo, диагностика, '
                            'сохранение с backup.',
                          ),
                        ],
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'diag',
                      child: Text('Проверить XML'),
                    ),
                    PopupMenuItem(
                      value: 'about',
                      child: Text('О программе'),
                    ),
                  ],
                ),
              ],
            ),
            body: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Text(
                    ctrl.filePath,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(label: Text('Quests: ${st.quests}')),
                      Chip(label: Text('Додзё: ${st.dojos}')),
                      Chip(label: Text('Include: ${st.includes}')),
                    ],
                  ),
                ),
                const Divider(height: 1),
                tile(
                  Icons.home_work,
                  'Выбор додзё (Dojo Changer)',
                  sub: '${st.dojos} додзё • листание NEXT / BACK / SELECT',
                  onTap: () => go(context, const DojoChangerScreen()),
                ),
                tile(
                  Icons.list_alt,
                  'Все квесты',
                  sub: '${st.quests} квестов • поиск, XML, атрибуты',
                  onTap: () => go(context, const QuestListScreen()),
                ),
                tile(
                  Icons.fact_check,
                  'Проверить quests.xml',
                  sub: 'Ошибок: ${diag.errors.length} • '
                      'Предупреждений: ${diag.warnings.length}',
                  onTap: () => go(context, const DiagnosticsScreen()),
                ),
                const SizedBox(height: 80),
              ],
            ),
            bottomNavigationBar: editorBottomBar(context),
          ),
        );
      },
    );
  }
}
