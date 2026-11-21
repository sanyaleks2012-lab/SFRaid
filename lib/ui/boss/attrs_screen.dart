import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../common/dialogs.dart';
import '../common/widgets.dart';

class AttrsScreen extends StatelessWidget {
  final XmlElement el;

  final String title;

  const AttrsScreen(this.el, this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final r = await form(
            context,
            'Добавить / изменить',
            {
              'Имя атрибута': '',
              'Значение': '',
            },
          );

          if (r == null || r['Имя атрибута']!.isEmpty) {
            return;
          }

          ctrl.setAttr(
            el,
            r['Имя атрибута']!,
            r['Значение']!,
          );
        },
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final attrs = el.attrMap.entries.toList();

          if (attrs.isEmpty) {
            return emptyNote('Атрибутов нет.');
          }

          return ListView(
            children: [
              for (final e in attrs)
                ListTile(
                  title: Text(e.key),
                  subtitle: Text(e.value),
                  onTap: () async {
                    final r = await form(
                      context,
                      e.key,
                      {'Значение': e.value},
                    );

                    if (r != null) {
                      ctrl.setAttr(
                        el,
                        e.key,
                        r['Значение']!,
                      );
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить ${e.key}?',
                      )) {
                        ctrl.removeAttr(el, e.key);
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
