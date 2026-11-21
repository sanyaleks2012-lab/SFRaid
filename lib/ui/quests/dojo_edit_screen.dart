import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../common/dialogs.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import '../xml/xml_edit_screen.dart';
import '../xml/xml_view_screen.dart';

class DojoEditScreen extends StatelessWidget {
  final String pageAction;

  const DojoEditScreen(this.pageAction, {super.key});

  Future<void> _editField(
    BuildContext context,
    String label,
    String current,
    void Function(String v) apply,
  ) async {
    final r = await form(context, label, {label: current});

    if (r == null || !context.mounted) return;

    guard(context, () => apply(r[label]!));
  }

  Future<void> _editXml(BuildContext context, XmlElement el) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => XmlEditScreen(el)),
    );

    if (ok == true && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final e = ctrl
            .dojos()
            .where((d) => d.pageAction == pageAction)
            .firstOrNull;

        if (e == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('ДОДЗЁ')),
            body: emptyNote('Додзё не найдено (удалено или изменён ActionID).'),
          );
        }

        final first = ctrl.dojos().first.pageAction == pageAction;

        return Scaffold(
          appBar: AppBar(title: Text('ДОДЗЁ — ${e.title}')),
          body: ListView(
            children: [
              tile(
                Icons.title,
                'Текст страницы (Line Text)',
                sub: e.labelKey.isEmpty ? '—' : e.labelKey,
                onTap: () => _editField(
                  context,
                  'Line Text',
                  e.labelKey,
                  (v) => ctrl.editDojo(pageAction, labelKey: v),
                ),
              ),
              tile(
                Icons.place,
                'Локация (ChangeDojoLocation)',
                sub: e.location.isEmpty ? '—' : e.location,
                onTap: () => _editField(
                  context,
                  'Location',
                  e.location,
                  (v) => ctrl.editDojo(pageAction, location: v),
                ),
              ),
              tile(
                Icons.bookmark,
                'DojoLoader (переменная выбора)',
                sub: e.loader.isEmpty ? '—' : e.loader,
                onTap: () => _editField(
                  context,
                  'DojoLoader',
                  e.loader,
                  (v) => ctrl.editDojo(pageAction, loader: v),
                ),
              ),
              const Divider(),
              tile(
                Icons.link,
                'ActionID',
                sub: 'Страница: ${e.pageAction}\n'
                    'SELECT → ${e.loadAction.isEmpty ? '—' : e.loadAction}',
                trailing: const SizedBox.shrink(),
              ),
              tile(
                Icons.restart_alt,
                'Стартовая загрузка',
                sub: e.startupIf != null
                    ? 'Есть (If _DojoLoader = ${e.loader})'
                    : (e.loader == 'Default'
                        ? 'Не нужна для Default'
                        : 'Нет — выбор не восстановится после перезапуска'),
                trailing: const SizedBox.shrink(),
              ),
              const Divider(),
              tile(
                Icons.code,
                'XML страницы',
                onTap: () => go(context, XmlViewScreen(e.page)),
              ),
              tile(
                Icons.edit_note,
                'Редактировать XML страницы',
                onTap: () => _editXml(context, e.page),
              ),
              if (e.load != null) ...[
                tile(
                  Icons.code,
                  'XML Load-квеста',
                  onTap: () => go(context, XmlViewScreen(e.load!)),
                ),
                tile(
                  Icons.edit_note,
                  'Редактировать XML Load-квеста',
                  onTap: () => _editXml(context, e.load!),
                ),
              ],
              if (!first)
                tile(
                  Icons.delete_forever,
                  'Удалить додзё',
                  sub: 'Page + Load + стартовая загрузка, цепочка '
                      'NEXT/BACK перестроится',
                  onTap: () async {
                    if (!await confirm(
                      context,
                      'Удалить додзё ${e.title}?',
                    )) {
                      return;
                    }

                    if (!context.mounted) return;

                    guard(context, () {
                      ctrl.deleteDojo(pageAction);
                      Navigator.of(context).pop();
                    });
                  },
                ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}
