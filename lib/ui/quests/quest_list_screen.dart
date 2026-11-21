import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../common/dialogs.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';
import 'quest_screen.dart';

final RegExp _tagRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_.\-]*$');

class QuestListScreen extends StatefulWidget {
  const QuestListScreen({super.key});

  @override
  State<QuestListScreen> createState() => _QuestListScreenState();
}

class _QuestListScreenState extends State<QuestListScreen> {
  String q = '';

  Future<void> _add() async {
    final r = await form(
      context,
      'Новый квест',
      {'Name': '', 'Event': 'ApplicationStart'},
      hint: 'Event: ApplicationStart, SessionStart, FightEnd, FightEnter, '
          'Activate, MapButtonPress …\n'
          'Тело (Conditions / Actions) правится через «Редактировать XML».',
    );

    if (r == null || !mounted) return;

    if (r['Name']!.isEmpty || !_tagRe.hasMatch(r['Event']!)) {
      toast(context, 'Нужны Name и корректный Event.');
      return;
    }

    final el = ctrl.addQuest(r['Name']!, r['Event']!);

    go(context, QuestScreen(el));
  }

  bool _match(XmlElement e, String lq) {
    if (lq.isEmpty) return true;

    return e.toXmlString().toLowerCase().contains(lq);
  }

  String _title(XmlElement e) {
    if (e.name.local == 'Quest') return e.attr('Name', '?');

    if (e.name.local == 'Include') return 'Include: ${e.attr('File', '?')}';

    return e.name.local;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final lq = q.trim().toLowerCase();

        final items =
            ctrl.root.childElements.where((e) => _match(e, lq)).toList();

        return Scaffold(
          appBar: AppBar(
            title: TextField(
              decoration: const InputDecoration(
                hintText: 'Поиск: имя, переменная, предмет, текст…',
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Квест'),
            onPressed: _add,
          ),
          body: items.isEmpty
              ? emptyNote('Ничего не найдено.')
              : ListView.builder(
                  itemCount: items.length + 1,
                  itemBuilder: (_, i) {
                    if (i == items.length) return const SizedBox(height: 80);

                    final el = items[i];

                    final isQuest = el.name.local == 'Quest';

                    final events = el.kid('Events')?.childElements
                            .map((x) => x.name.local)
                            .join(', ') ??
                        '';

                    final prio = el.getAttribute('Priority');

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isQuest ? Icons.bolt : Icons.attach_file,
                      ),
                      title: Text(_title(el)),
                      subtitle: isQuest
                          ? Text(
                              [
                                if (events.isNotEmpty) events,
                                if (prio != null) 'Priority=$prio',
                              ].join(' • '),
                            )
                          : null,
                      onTap: () => go(context, QuestScreen(el)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'dup') {
                            final r = await form(
                              context,
                              'Дублировать',
                              {'Name': '${el.attr('Name', 'Quest')}_COPY'},
                            );

                            if (r != null) {
                              ctrl.duplicateRootElement(el, r['Name']!);
                            }
                          } else if (v == 'del') {
                            if (await confirm(
                              context,
                              'Удалить ${_title(el)}?',
                            )) {
                              ctrl.removeChild(el);
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          if (isQuest)
                            const PopupMenuItem(
                              value: 'dup',
                              child: Text('Дублировать'),
                            ),
                          const PopupMenuItem(
                            value: 'del',
                            child: Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
