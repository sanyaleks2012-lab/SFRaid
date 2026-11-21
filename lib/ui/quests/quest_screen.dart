import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../boss/attrs_screen.dart';
import '../common/dialogs.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import '../xml/xml_edit_screen.dart';
import '../xml/xml_view_screen.dart';

String _childTags(XmlElement? n) {
  if (n == null) return '—';

  final tags = n.childElements.map((e) => e.name.local).toList();

  if (tags.isEmpty) return '—';

  final shown = tags.take(8).join(', ');

  return tags.length > 8 ? '$shown … (+${tags.length - 8})' : shown;
}

class QuestScreen extends StatelessWidget {
  final XmlElement el;

  const QuestScreen(this.el, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final isQuest = el.name.local == 'Quest';

        return Scaffold(
          appBar: AppBar(
            title: Text(
              isQuest
                  ? 'КВЕСТ — ${el.attr('Name', '?')}'
                  : el.name.local.toUpperCase(),
            ),
          ),
          body: ListView(
            children: [
              if (isQuest) ...[
                tile(
                  Icons.edit,
                  'Name',
                  sub: el.attr('Name', '—'),
                  onTap: () async {
                    final r = await form(
                      context,
                      'Name',
                      {'Name': el.attr('Name')},
                    );

                    if (r == null) return;

                    if (r['Name']!.isEmpty) {
                      if (context.mounted) {
                        toast(context, 'Name не может быть пустым.');
                      }
                      return;
                    }

                    ctrl.changeAttr(el, 'Name', r['Name']!);
                  },
                ),
                tile(
                  Icons.priority_high,
                  'Priority',
                  sub: el.getAttribute('Priority') ?? '—',
                  onTap: () async {
                    final r = await form(
                      context,
                      'Priority',
                      {'Priority': el.attr('Priority')},
                      hint: 'Пусто — удалить атрибут',
                    );

                    if (r == null) return;

                    if (r['Priority']!.isEmpty) {
                      if (el.getAttribute('Priority') != null) {
                        ctrl.removeAttr(el, 'Priority');
                      }
                    } else {
                      ctrl.changeAttr(el, 'Priority', r['Priority']!);
                    }
                  },
                ),
              ],
              tile(
                Icons.tune,
                'Атрибуты',
                sub: '${el.attributes.length}',
                onTap: () => go(context, AttrsScreen(el, 'Атрибуты')),
              ),
              if (isQuest) ...[
                tile(
                  Icons.flash_on,
                  'Events',
                  sub: _childTags(el.kid('Events')),
                  trailing: const SizedBox.shrink(),
                ),
                tile(
                  Icons.rule,
                  'Conditions',
                  sub: _childTags(el.kid('Conditions')),
                  trailing: const SizedBox.shrink(),
                ),
                tile(
                  Icons.play_arrow,
                  'Actions',
                  sub: _childTags(el.kid('Actions')),
                  trailing: const SizedBox.shrink(),
                ),
              ],
              tile(
                Icons.edit_note,
                'Редактировать XML',
                sub: 'Полная правка Events / Conditions / Actions',
                onTap: () async {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => XmlEditScreen(el)),
                  );

                  if (ok == true && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              tile(
                Icons.code,
                'Просмотр XML',
                onTap: () => go(context, XmlViewScreen(el)),
              ),
              if (isQuest)
                tile(
                  Icons.content_copy,
                  'Дублировать',
                  onTap: () async {
                    final r = await form(
                      context,
                      'Дублировать',
                      {'Name': '${el.attr('Name', 'Quest')}_COPY'},
                    );

                    if (r != null) {
                      ctrl.duplicateRootElement(el, r['Name']!);

                      if (context.mounted) {
                        toast(context, 'Копия добавлена после оригинала.');
                      }
                    }
                  },
                ),
              tile(
                Icons.delete_forever,
                'Удалить',
                onTap: () async {
                  if (await confirm(context, 'Удалить этот элемент?')) {
                    ctrl.removeChild(el);

                    if (context.mounted) Navigator.of(context).pop();
                  }
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
