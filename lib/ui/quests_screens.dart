import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../core/xml_utils.dart';
import 'widgets.dart';

final _tagRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_.\-]*$');

void _go(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));

String _childTags(XmlElement? n) {
  if (n == null) return tr('common.none');
  final tags = n.childElements.map((e) => e.name.local).toList();
  if (tags.isEmpty) return tr('common.none');
  final shown = tags.take(8).join(', ');
  return tags.length > 8 ? '$shown … (+${tags.length - 8})' : shown;
}

void showIssuesSheet(BuildContext context, RaidForgeController ctrl) {
  final issues = ctrl.diagnostics();
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Text(tr('diag.title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (issues.isEmpty)
          Text(tr('diag.ok'), style: const TextStyle(color: Colors.greenAccent)),
        for (final i in issues)
          ListTile(
            dense: true,
            leading: Icon(
              i.error ? Icons.error_outline : Icons.warning_amber,
              color: i.error ? Colors.redAccent : Colors.amber,
            ),
            title: Text(tr(i.key, i.args)),
          ),
      ],
    ),
  );
}

class EditorBar extends StatelessWidget {
  final RaidForgeController ctrl;
  const EditorBar({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 64,
      child: Row(
        children: [
          IconButton(
            tooltip: tr('home.undo', {'count': ctrl.undoCount, 'max': maxUndo}),
            icon: Badge(
              isLabelVisible: ctrl.undoCount > 0,
              label: Text('${ctrl.undoCount}'),
              child: const Icon(Icons.undo),
            ),
            onPressed: () {
              if (!ctrl.undo()) snack(context, tr('err.undoEmpty'));
            },
          ),
          IconButton(
            tooltip: tr('home.save'),
            icon: const Icon(Icons.save_outlined),
            onPressed: () => saveWithFeedback(context, ctrl),
          ),
          const Spacer(),
          Text(
            ctrl.dirty ? tr('home.dirty') : tr('toast.saved'),
            style: TextStyle(
              fontSize: 11,
              color: ctrl.dirty
                  ? Theme.of(context).colorScheme.tertiary
                  : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// QUESTS HOME
// ------------------------------------------------------------

class QuestsHomeScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  const QuestsHomeScreen({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final dojos = ctrl.dojos().length;
        final quests = ctrl.quests().length;
        final includes = ctrl.root.kids('Include').length;
        final issues = ctrl.diagnostics().length;
        return PopScope(
          canPop: !ctrl.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await confirmDialog(context, tr('home.exitTitle')) &&
                context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(ctrl.dirty
                  ? '${tr('quests.title')}  ●'
                  : tr('quests.title')),
            ),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(ctrl.filePath,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text('${tr('quests.quests')}: $quests')),
                    Chip(label: Text('${tr('quests.dojo')}: $dojos')),
                    Chip(label: Text('${tr('quests.includes')}: $includes')),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.home_work_outlined),
                        title: Text(tr('quests.dojoChanger')),
                        subtitle: Text(tr('quests.dojoSub', {'count': dojos})),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _go(context, DojoChangerScreen(ctrl: ctrl)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.list_alt),
                        title: Text(tr('quests.allQuests')),
                        subtitle: Text(tr('quests.allSub', {'count': quests})),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _go(context, QuestListScreen(ctrl: ctrl)),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.fact_check_outlined),
                        title: Text(tr('diag.title')),
                        subtitle: Text(issues > 0 ? '$issues' : tr('diag.ok')),
                        onTap: () => showIssuesSheet(context, ctrl),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: EditorBar(ctrl: ctrl),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------
// DOJO CHANGER
// ------------------------------------------------------------

class DojoChangerScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  const DojoChangerScreen({super.key, required this.ctrl});

  Future<void> _add(BuildContext context) async {
    final r = await showFieldsSheet(
      context,
      tr('dojo.add'),
      [
        FieldSpec('id', tr('dojo.id'), ''),
        FieldSpec('loc', tr('dojo.location'), ''),
        FieldSpec('label', tr('dojo.labelKey'), ''),
        FieldSpec('loader', tr('dojo.loader'), ''),
      ],
      hint: tr('dojo.hintAdd'),
    );
    if (r == null || !context.mounted) return;
    guard(
      context,
      () => ctrl.addDojo(
        id: r['id']!,
        location: r['loc']!,
        labelKey: r['label']!,
        loader: r['loader']!,
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
          appBar: AppBar(title: Text(tr('quests.dojoChanger'))),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(tr('dojo.add')),
            onPressed: () => _add(context),
          ),
          body: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('dojo.empty'), textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                  children: [
                    for (var i = 0; i < list.length; i++)
                      _tile(context, list, i),
                  ],
                ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, List<DojoEntry> list, int i) {
    final d = list[i];
    final warnings = <String>[
      if (d.startupIf == null && d.loader != 'Default' && d.loader.isNotEmpty)
        tr('dojo.noStartup'),
      if (!d.linked) tr('dojo.unlinked'),
    ];
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(d.title),
      subtitle: Text([
        d.location.isEmpty ? tr('common.none') : d.location,
        d.loader.isEmpty ? tr('common.none') : d.loader,
        ...warnings,
      ].join(' • ')),
      onTap: () => _go(
        context,
        DojoEditScreen(ctrl: ctrl, pageAction: d.pageAction),
      ),
      trailing: i == 0
          ? const Icon(Icons.lock_outline, size: 18)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: tr('dojo.up'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: i <= 1
                      ? null
                      : () => ctrl.moveDojo(d.pageAction, -1),
                ),
                IconButton(
                  tooltip: tr('dojo.down'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: i >= list.length - 1
                      ? null
                      : () => ctrl.moveDojo(d.pageAction, 1),
                ),
              ],
            ),
    );
  }
}

class DojoEditScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  final String pageAction;
  const DojoEditScreen({
    super.key,
    required this.ctrl,
    required this.pageAction,
  });

  Future<void> _field(
    BuildContext context,
    String label,
    String current,
    void Function(String v) apply,
  ) async {
    final r = await showFieldsSheet(
      context,
      label,
      [FieldSpec('v', label, current)],
    );
    if (r == null || !context.mounted) return;
    guard(context, () => apply(r['v']!));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final all = ctrl.dojos();
        final e = all.where((d) => d.pageAction == pageAction).firstOrNull;
        if (e == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('dojo.notFound'))),
          );
        }
        final first = all.first.pageAction == pageAction;
        final startupText = e.startupIf != null
            ? tr('dojo.startupYes', {'loader': e.loader})
            : (e.loader == 'Default'
                ? tr('dojo.startupDefault')
                : tr('dojo.startupNo'));

        return Scaffold(
          appBar: AppBar(title: Text(e.title)),
          body: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.title),
                title: Text(tr('dojo.pageText')),
                subtitle: Text(e.labelKey.isEmpty ? tr('common.none') : e.labelKey),
                onTap: () => _field(context, tr('dojo.labelKey'), e.labelKey,
                    (v) => ctrl.editDojo(pageAction, labelKey: v)),
              ),
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(tr('dojo.location')),
                subtitle: Text(e.location.isEmpty ? tr('common.none') : e.location),
                onTap: () => _field(context, tr('dojo.location'), e.location,
                    (v) => ctrl.editDojo(pageAction, location: v)),
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(tr('dojo.loader')),
                subtitle: Text(e.loader.isEmpty ? tr('common.none') : e.loader),
                onTap: () => _field(context, tr('dojo.loader'), e.loader,
                    (v) => ctrl.editDojo(pageAction, loader: v)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(tr('dojo.actionId')),
                subtitle: Text(
                  '${e.pageAction}\n${tr('dojo.select')} → '
                  '${e.loadAction.isEmpty ? tr('common.none') : e.loadAction}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: Text(tr('dojo.startup')),
                subtitle: Text(startupText),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(tr('dojo.xmlPage')),
                onTap: () => _go(context,
                    XmlScreen(ctrl: ctrl, el: e.page, editable: false)),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(tr('dojo.xmlPageEdit')),
                onTap: () => _go(context,
                    XmlScreen(ctrl: ctrl, el: e.page, editable: true)),
              ),
              if (e.load != null) ...[
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(tr('dojo.xmlLoad')),
                  onTap: () => _go(context,
                      XmlScreen(ctrl: ctrl, el: e.load!, editable: false)),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text(tr('dojo.xmlLoadEdit')),
                  onTap: () => _go(context,
                      XmlScreen(ctrl: ctrl, el: e.load!, editable: true)),
                ),
              ],
              if (!first)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: Text(tr('common.delete')),
                  subtitle: Text(tr('dojo.deleteHint')),
                  onTap: () async {
                    if (!await confirmDialog(
                        context, tr('dojo.deleteTitle', {'title': e.title}))) {
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

// ------------------------------------------------------------
// ALL QUESTS
// ------------------------------------------------------------

class QuestListScreen extends StatefulWidget {
  final RaidForgeController ctrl;
  const QuestListScreen({super.key, required this.ctrl});

  @override
  State<QuestListScreen> createState() => _QuestListScreenState();
}

class _QuestListScreenState extends State<QuestListScreen> {
  String _q = '';

  Future<void> _add() async {
    final r = await showFieldsSheet(
      context,
      tr('quests.add'),
      [
        FieldSpec('name', tr('quests.name'), ''),
        FieldSpec('event', tr('quests.event'), 'ApplicationStart'),
      ],
      hint: tr('quests.hintAdd'),
    );
    if (r == null || !mounted) return;
    if (r['name']!.isEmpty || !_tagRe.hasMatch(r['event']!)) {
      snack(context, tr('quests.errName'));
      return;
    }
    final el = widget.ctrl.addQuest(r['name']!, r['event']!);
    final idx = widget.ctrl.rootChildren().indexOf(el);
    _go(context, QuestScreen(ctrl: widget.ctrl, index: idx));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ctrl,
      builder: (context, _) {
        final lq = _q.trim().toLowerCase();
        final all = widget.ctrl.rootChildren();
        final items = <int>[
          for (var i = 0; i < all.length; i++)
            if (lq.isEmpty || all[i].toXmlString().toLowerCase().contains(lq)) i,
        ];
        return Scaffold(
          appBar: AppBar(
            title: TextField(
              decoration: InputDecoration(
                hintText: tr('quests.search'),
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(tr('quests.add')),
            onPressed: _add,
          ),
          body: items.isEmpty
              ? Center(child: Text(tr('common.none')))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  itemBuilder: (_, k) {
                    final i = items[k];
                    final el = all[i];
                    final isQuest = el.name.local == 'Quest';
                    final events = el
                            .kid('Events')
                            ?.childElements
                            .map((x) => x.name.local)
                            .join(', ') ??
                        '';
                    final prio = el.getAttribute('Priority');
                    final title = isQuest
                        ? el.attr('Name', '?')
                        : '${tr('quests.include')}: ${el.attr('File', '?')}';

                    return ListTile(
                      dense: true,
                      leading: Icon(isQuest ? Icons.bolt : Icons.attach_file),
                      title: Text(title),
                      subtitle: isQuest
                          ? Text([
                              if (events.isNotEmpty) events,
                              if (prio != null) 'Priority=$prio',
                            ].join(' • '))
                          : null,
                      onTap: () =>
                          _go(context, QuestScreen(ctrl: widget.ctrl, index: i)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'dup') {
                            final r = await showFieldsSheet(
                              context,
                              tr('quests.duplicate'),
                              [
                                FieldSpec('name', tr('quests.name'),
                                    '${el.attr('Name', 'Quest')}_COPY'),
                              ],
                            );
                            if (r == null || !context.mounted) return;
                            guard(context,
                                () => widget.ctrl.duplicateRootElement(el, r['name']!));
                          } else if (v == 'del') {
                            final ok = await confirmDialog(
                              context,
                              tr('quests.deleteQuest', {'name': title}),
                            );
                            if (ok && mounted) widget.ctrl.removeNode(el);
                          }
                        },
                        itemBuilder: (_) => [
                          if (isQuest)
                            PopupMenuItem(
                              value: 'dup',
                              child: Text(tr('quests.duplicate')),
                            ),
                          PopupMenuItem(
                            value: 'del',
                            child: Text(tr('common.delete')),
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

// ------------------------------------------------------------
// QUEST / INCLUDE
// ------------------------------------------------------------

class QuestScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  final int index;
  const QuestScreen({super.key, required this.ctrl, required this.index});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final all = ctrl.rootChildren();
        if (index < 0 || index >= all.length) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(tr('common.none'))),
          );
        }
        final el = all[index];
        final isQuest = el.name.local == 'Quest';
        final title = isQuest ? el.attr('Name', '?') : el.name.local;

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(
            children: [
              if (isQuest) ...[
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(tr('quests.name')),
                  subtitle: Text(el.attr('Name', tr('common.none'))),
                  onTap: () async {
                    final r = await showFieldsSheet(context, tr('quests.name'),
                        [FieldSpec('v', tr('quests.name'), el.attr('Name'))]);
                    if (r == null || !context.mounted) return;
                    if (r['v']!.isEmpty) {
                      snack(context, tr('err.nameEmpty'));
                      return;
                    }
                    ctrl.setAttr(el, 'Name', r['v']!);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.priority_high),
                  title: Text(tr('quests.priority')),
                  subtitle: Text(el.getAttribute('Priority') ?? tr('common.none')),
                  onTap: () async {
                    final r = await showFieldsSheet(
                      context,
                      tr('quests.priority'),
                      [FieldSpec('v', tr('quests.priority'), el.attr('Priority'), numeric: true)],
                      hint: tr('quests.priorityHint'),
                    );
                    if (r == null || !context.mounted) return;
                    if (r['v']!.isEmpty) {
                      ctrl.removeAttr(el, 'Priority');
                    } else {
                      ctrl.setAttr(el, 'Priority', r['v']!);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flash_on),
                  title: Text(tr('quests.events')),
                  subtitle: Text(_childTags(el.kid('Events'))),
                ),
                ListTile(
                  leading: const Icon(Icons.rule),
                  title: Text(tr('quests.conditions')),
                  subtitle: Text(_childTags(el.kid('Conditions'))),
                ),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(tr('quests.actions')),
                  subtitle: Text(_childTags(el.kid('Actions'))),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(tr('quests.attrs')),
                subtitle: Text('${el.attributes.length}'),
                onTap: () => _go(context,
                    AttrsScreen(ctrl: ctrl, el: el, title: tr('quests.attrs'))),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: Text(tr('quests.xmlEdit')),
                onTap: () => _go(context,
                    XmlScreen(ctrl: ctrl, el: el, editable: true)),
              ),
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(tr('quests.xmlView')),
                onTap: () => _go(context,
                    XmlScreen(ctrl: ctrl, el: el, editable: false)),
              ),
              if (isQuest)
                ListTile(
                  leading: const Icon(Icons.content_copy),
                  title: Text(tr('quests.duplicate')),
                  onTap: () async {
                    final r = await showFieldsSheet(
                      context,
                      tr('quests.duplicate'),
                      [FieldSpec('name', tr('quests.name'), '${el.attr('Name', 'Quest')}_COPY')],
                    );
                    if (r == null || !context.mounted) return;
                    guard(context, () => ctrl.duplicateRootElement(el, r['name']!));
                    snack(context, tr('quests.duplicate'));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: Text(tr('common.delete')),
                onTap: () async {
                  if (!await confirmDialog(context, tr('quests.deleteQuest', {'name': title}))) {
                    return;
                  }
                  if (!context.mounted) return;
                  ctrl.removeNode(el);
                  Navigator.of(context).pop();
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

class AttrsScreen extends StatelessWidget {
  final RaidForgeController ctrl;
  final XmlElement el;
  final String title;
  const AttrsScreen({
    super.key,
    required this.ctrl,
    required this.el,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final attrs = el.attributes.toList();
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          floatingActionButton: FloatingActionButton(
            tooltip: tr('attr.add'),
            child: const Icon(Icons.add),
            onPressed: () async {
              final r = await showFieldsSheet(context, tr('attr.add'), [
                FieldSpec('key', tr('attr.key'), ''),
                FieldSpec('value', tr('attr.value'), ''),
              ]);
              if (r == null || r['key']!.isEmpty) return;
              ctrl.setAttr(el, r['key']!, r['value']!);
            },
          ),
          body: attrs.isEmpty
              ? Center(child: Text(tr('common.none')))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final a in attrs)
                      ListTile(
                        title: Text(a.name.qualified),
                        subtitle: Text(a.value),
                        onTap: () async {
                          final r = await showFieldsSheet(context, a.name.qualified,
                              [FieldSpec('value', tr('attr.value'), a.value)]);
                          if (r == null) return;
                          ctrl.setAttr(el, a.name.qualified, r['value']!);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => ctrl.removeAttr(el, a.name.qualified),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

// ------------------------------------------------------------
// RAW XML VIEW / EDIT
// ------------------------------------------------------------

class XmlScreen extends StatefulWidget {
  final RaidForgeController ctrl;
  final XmlElement el;
  final bool editable;
  const XmlScreen({
    super.key,
    required this.ctrl,
    required this.el,
    required this.editable,
  });

  @override
  State<XmlScreen> createState() => _XmlScreenState();
}

class _XmlScreenState extends State<XmlScreen> {
  late final TextEditingController _c =
      TextEditingController(text: widget.ctrl.elementToXml(widget.el));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _apply() {
    guard(context, () {
      widget.ctrl.replaceElementXml(widget.el, _c.text);
      Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.el.name.local),
        actions: [
          if (widget.editable)
            IconButton(
              tooltip: tr('common.save'),
              icon: const Icon(Icons.check),
              onPressed: _apply,
            ),
        ],
      ),
      body: widget.editable
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _c,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                style: mono,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              scrollDirection: Axis.horizontal,
              child: SelectableText(_c.text, style: mono),
            ),
    );
  }
}