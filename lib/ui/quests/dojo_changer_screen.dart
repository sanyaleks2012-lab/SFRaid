import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../common/dialogs.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import 'dojo_edit_screen.dart';

class DojoChangerScreen extends StatelessWidget {
  const DojoChangerScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final r = await form(
      context,
      'Новое додзё',
      {
        'Id': '',
        'Location': '',
        'Text key (Line Text)': '',
        'DojoLoader': '',
      },
      hint: 'Id — латиница без пробелов, например Halloween26.\n'
          'Location — имя локации для ChangeDojoLocation '
          '(например dojo_hw26).\n'
          'Text key — ключ текста в диалоге (пусто = Dojo<Id>).\n'
          'DojoLoader — значение переменной (пусто = Id).',
    );

    if (r == null || !context.mounted) return;

    guard(
      context,
      () => ctrl.addDojo(
        id: r['Id']!,
        location: r['Location']!,
        labelKey: r['Text key (Line Text)']!,
        loader: r['DojoLoader']!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final list = ctrl.dojos();

        return Scaffold(
          appBar: AppBar(title: const Text('ВЫБОР ДОДЗЁ')),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Додзё'),
            onPressed: () => _add(context),
          ),
          body: list.isEmpty
              ? emptyNote(
                  'Страницы выбора додзё не найдены.\n'
                  'Нажми «Додзё», чтобы создать первую.',
                )
              : ListView(
                  children: [
                    for (var i = 0; i < list.length; i++)
                      ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        title: Text(list[i].title),
                        subtitle: Text(
                          '${list[i].location.isEmpty ? '—' : list[i].location}'
                          ' • ${list[i].loader.isEmpty ? '—' : list[i].loader}'
                          '${list[i].startupIf == null && list[i].loader != 'Default' && list[i].loader.isNotEmpty ? '\n⚠ нет стартовой загрузки' : ''}'
                          '${list[i].linked ? '' : '\n⚠ вне цепочки NEXT'}',
                        ),
                        isThreeLine: list[i].startupIf == null ||
                            !list[i].linked,
                        onTap: () => go(
                          context,
                          DojoEditScreen(list[i].pageAction),
                        ),
                        trailing: i == 0
                            ? const Icon(Icons.lock_outline, size: 18)
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Выше',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.arrow_upward),
                                    onPressed: i <= 1
                                        ? null
                                        : () => ctrl.moveDojo(
                                              list[i].pageAction,
                                              -1,
                                            ),
                                  ),
                                  IconButton(
                                    tooltip: 'Ниже',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.arrow_downward),
                                    onPressed: i >= list.length - 1
                                        ? null
                                        : () => ctrl.moveDojo(
                                              list[i].pageAction,
                                              1,
                                            ),
                                  ),
                                ],
                              ),
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
        );
      },
    );
  }
}
