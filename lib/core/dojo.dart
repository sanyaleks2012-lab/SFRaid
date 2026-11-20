part of 'raid_controller.dart';

const _actionIdVar = r'_$ActionID';
const _dojoTitle = 'DojoChangerTitle';
const _startupQuest = 'DojoChanger_LoadSelectedDojo';

const _dojoPageTemplate = r'''
<Quest Name="">
  <Events>
    <Activate />
  </Events>
  <Conditions>
    <Equal Value1="_$ActionID" Value2="" />
  </Conditions>
  <Actions>
    <Dialog Type="Multiline" Title="DojoChangerTitle" Image="man_random_small">
      <Line Text="" />
      <Button Type="Right" Color="Beige" Text="NEXT">
        <Activate ActionID="" />
      </Button>
      <Button Type="Middle" Color="Green" Text="SELECT">
        <Activate ActionID="" />
      </Button>
      <Button Type="Left" Color="Red" Text="BACK" />
      <CheckBox Text="ShowIntro" InitialValue="_ShowIntroVideo">
        <On>
          <SetVariable Scope="Users" Name="ShowIntroVideo" Value="1" />
        </On>
        <Off>
          <SetVariable Scope="Users" Name="ShowIntroVideo" Value="0" />
        </Off>
      </CheckBox>
    </Dialog>
  </Actions>
</Quest>''';

const _dojoLoadTemplate = r'''
<Quest Name="">
  <Events>
    <Activate />
  </Events>
  <Conditions>
    <Equal Value1="_$ActionID" Value2="" />
  </Conditions>
  <Actions>
    <ChangeDojoLocation Name="" />
    <ChangeScene Destination="Dojo" />
    <SetVariable Scope="Users" Name="DojoLoader" Value="" />
  </Actions>
</Quest>''';

const _dojoStartupQuestTemplate = '''
<Quest Name="DojoChanger_LoadSelectedDojo" Priority="999">
  <Events>
    <ApplicationStart />
  </Events>
  <Actions />
</Quest>''';

const _dojoStartupIfTemplate = '''
<If>
  <Conditions>
    <Equal Value1="_DojoLoader" Value2="" />
  </Conditions>
  <Then>
    <ChangeDojoLocation Name="" />
  </Then>
</If>''';

class DojoEntry {
  final XmlElement page;
  final XmlElement? load;
  final XmlElement? startupIf;
  final String pageAction;
  final String loadAction;
  final String labelKey;
  final String location;
  final String loader;
  final bool linked;

  const DojoEntry({
    required this.page,
    required this.load,
    required this.startupIf,
    required this.pageAction,
    required this.loadAction,
    required this.labelKey,
    required this.location,
    required this.loader,
    required this.linked,
  });

  String get title => labelKey.isEmpty ? pageAction : labelKey;
}

extension DojoOps on RaidForgeController {
  String? _actionCond(XmlElement quest) {
    final conds = quest.kid('Conditions');
    if (conds == null) return null;
    for (final e in conds.kids('Equal')) {
      if (e.attr('Value1') == _actionIdVar) return e.attr('Value2');
    }
    return null;
  }

  bool _onActivate(XmlElement q) => q.kid('Events')?.kid('Activate') != null;

  XmlElement? _dialogOf(XmlElement page) =>
      page.kid('Actions')?.kid('Dialog');

  XmlElement? _buttonOf(XmlElement dialog, String type) => dialog
      .kids('Button')
      .where((b) => b.attr('Type') == type)
      .firstOrNull;

  String? _buttonTarget(XmlElement dialog, String type) =>
      _buttonOf(dialog, type)?.kid('Activate')?.attr('ActionID');

  void _setButtonTarget(XmlElement dialog, String type, String? target) {
    final btn = _buttonOf(dialog, type);
    if (btn == null) return;
    final act = btn.kid('Activate');
    if (target == null) {
      act?.remove();
      return;
    }
    if (act == null) {
      btn.children.add(makeEl('Activate', {'ActionID': target}));
    } else {
      act.put('ActionID', target);
    }
  }

  XmlElement? _startupIfFor(String loader) {
    for (final i in root.findAllElements('If')) {
      final conds = i.kid('Conditions');
      if (conds == null) continue;
      for (final e in conds.kids('Equal')) {
        if (e.attr('Value1') == '_DojoLoader' && e.attr('Value2') == loader) {
          return i;
        }
      }
    }
    return null;
  }

  /// Додзё в порядке листания: DefaultPage → NEXT → NEXT ...
  List<DojoEntry> dojos() {
    final pages = <String, XmlElement>{};
    final loads = <String, XmlElement>{};

    for (final q in quests()) {
      if (!_onActivate(q)) continue;
      final id = _actionCond(q);
      if (id == null) continue;
      final dialog = _dialogOf(q);
      if (dialog != null && dialog.attr('Title') == _dojoTitle) {
        pages.putIfAbsent(id, () => q);
      } else if (q.kid('Actions')?.kid('ChangeDojoLocation') != null) {
        loads.putIfAbsent(id, () => q);
      }
    }

    final order = <String>[];
    String? cur = pages.containsKey('DefaultPage')
        ? 'DefaultPage'
        : pages.keys.firstOrNull;
    while (cur != null && pages.containsKey(cur) && !order.contains(cur)) {
      order.add(cur);
      cur = _buttonTarget(_dialogOf(pages[cur]!)!, 'Right');
    }
    final linked = order.toSet();
    for (final k in pages.keys) {
      if (!linked.contains(k)) order.add(k);
    }

    final result = <DojoEntry>[];
    for (final pa in order) {
      final page = pages[pa]!;
      final dialog = _dialogOf(page)!;
      final loadAction = _buttonTarget(dialog, 'Middle') ?? '';
      final load = loads[loadAction];
      final actions = load?.kid('Actions');

      var loader = '';
      if (actions != null) {
        for (final s in actions.kids('SetVariable')) {
          if (s.attr('Name') == 'DojoLoader') {
            loader = s.attr('Value');
            break;
          }
        }
      }

      result.add(DojoEntry(
        page: page,
        load: load,
        startupIf: loader.isEmpty ? null : _startupIfFor(loader),
        pageAction: pa,
        loadAction: loadAction,
        labelKey: dialog.kid('Line')?.attr('Text') ?? '',
        location: actions?.kid('ChangeDojoLocation')?.attr('Name') ?? '',
        loader: loader,
        linked: linked.contains(pa),
      ));
    }
    return result;
  }

  /// Перепривязывает NEXT / BACK по порядку (последняя страница ведёт на первую).
  void _relinkChain(List<DojoEntry> order) {
    for (var i = 0; i < order.length; i++) {
      final dialog = _dialogOf(order[i].page);
      if (dialog == null) continue;
      _setButtonTarget(
        dialog,
        'Right',
        order[(i + 1) % order.length].pageAction,
      );
      _setButtonTarget(
        dialog,
        'Left',
        i == 0 ? null : order[i - 1].pageAction,
      );
    }
  }

  void _addStartup(String loader, String location) {
    var q = quests().where((x) => x.attr('Name') == _startupQuest).firstOrNull;
    if (q == null) {
      final nq = parseFragment(_dojoStartupQuestTemplate);
      root.children.add(nq);
      q = nq;
    }
    var actions = q.kid('Actions');
    if (actions == null) {
      actions = makeEl('Actions');
      q.children.add(actions);
    }
    final iff = parseFragment(_dojoStartupIfTemplate);
    iff.kid('Conditions')!.kid('Equal')!.put('Value2', loader);
    iff.kid('Then')!.kid('ChangeDojoLocation')!.put('Name', location);
    actions.children.add(iff);
  }

  void addDojo({
    required String id,
    required String location,
    String labelKey = '',
    String loader = '',
  }) {
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(id)) {
      throw RaidForgeException('dojo.errId');
    }
    if (location.isEmpty) throw RaidForgeException('dojo.errLocation');

    final pageAction = '${id}Page';
    final loadAction = 'Dojo$id';
    final label = labelKey.isEmpty ? 'Dojo$id' : labelKey;
    final loaderValue = loader.isEmpty ? id : loader;

    final existing = dojos();
    if (existing.any(
      (d) => d.pageAction == pageAction || d.loadAction == loadAction,
    )) {
      throw RaidForgeException('dojo.errExists', {'id': id});
    }
    if (existing.any((d) => d.loader == loaderValue)) {
      throw RaidForgeException('dojo.errLoaderTaken', {'loader': loaderValue});
    }

    final pageName = 'Dojo${id}_Page';
    final loadName = 'Dojo${id}_Load';
    if (quests().any(
      (q) => q.attr('Name') == pageName || q.attr('Name') == loadName,
    )) {
      throw RaidForgeException('dojo.errQuestExists', {'name': pageName});
    }

    _mutate(() {
      final page = parseFragment(_dojoPageTemplate);
      page.put('Name', pageName);
      page.kid('Conditions')!.kid('Equal')!.put('Value2', pageAction);

      final dialog = page.kid('Actions')!.kid('Dialog')!;
      dialog.kid('Line')!.put('Text', label);
      _setButtonTarget(dialog, 'Middle', loadAction);

      final load = parseFragment(_dojoLoadTemplate);
      load.put('Name', loadName);
      load.kid('Conditions')!.kid('Equal')!.put('Value2', loadAction);
      final la = load.kid('Actions')!;
      la.kid('ChangeDojoLocation')!.put('Name', location);
      la.kid('SetVariable')!.put('Value', loaderValue);

      root.children.add(page);
      root.children.add(load);
      _addStartup(loaderValue, location);

      // Новая страница не связана с цепочкой, поэтому dojos() поставит её последней.
      _relinkChain(dojos());
    });
  }

  void editDojo(
    String pageAction, {
    String? labelKey,
    String? location,
    String? loader,
  }) {
    final all = dojos();
    final e = all.where((d) => d.pageAction == pageAction).firstOrNull;
    if (e == null) throw RaidForgeException('dojo.errNotFound');

    if (labelKey != null && labelKey.isEmpty) {
      throw RaidForgeException('dojo.errLineEmpty');
    }
    if (location != null && location.isEmpty) {
      throw RaidForgeException('dojo.errLocationEmpty');
    }
    if (loader != null) {
      if (loader.isEmpty) throw RaidForgeException('dojo.errLoaderEmpty');
      if (all.any((d) => d.pageAction != pageAction && d.loader == loader)) {
        throw RaidForgeException('dojo.errLoaderTaken', {'loader': loader});
      }
    }

    final changed = (labelKey != null && labelKey != e.labelKey) ||
        (location != null && location != e.location) ||
        (loader != null && loader != e.loader);
    if (!changed) return;

    _mutate(() {
      if (labelKey != null) {
        _dialogOf(e.page)?.kid('Line')?.put('Text', labelKey);
      }
      if (location != null) {
        e.load?.kid('Actions')?.kid('ChangeDojoLocation')?.put('Name', location);
        final si = e.startupIf;
        if (si != null) {
          for (final c in si.findAllElements('ChangeDojoLocation').toList()) {
            c.put('Name', location);
          }
        }
      }
      if (loader != null) {
        final la = e.load?.kid('Actions');
        if (la != null) {
          for (final s in la.kids('SetVariable').toList()) {
            if (s.attr('Name') == 'DojoLoader') s.put('Value', loader);
          }
        }
        final conds = e.startupIf?.kid('Conditions');
        if (conds != null) {
          for (final c in conds.kids('Equal').toList()) {
            if (c.attr('Value1') == '_DojoLoader') c.put('Value2', loader);
          }
        }
      }
    });
  }

  void deleteDojo(String pageAction) {
    final all = dojos();
    final e = all.where((d) => d.pageAction == pageAction).firstOrNull;
    if (e == null) return;
    if (all.first.pageAction == pageAction) {
      throw RaidForgeException('dojo.errFirst');
    }
    final rest = all.where((d) => d.pageAction != pageAction).toList();

    _mutate(() {
      final si = e.startupIf;
      XmlElement? owner;
      if (si != null) {
        owner = si.ancestors
            .whereType<XmlElement>()
            .where((a) => a.name.local == 'Quest')
            .firstOrNull;
        si.remove();
      }
      e.page.remove();
      e.load?.remove();

      // Стартовый квест без действий больше не нужен.
      if (owner != null && owner.attr('Name') != _startupQuest) {
        final act = owner.kid('Actions');
        if (act == null || act.childElements.isEmpty) owner.remove();
      }
      _relinkChain(rest);
    });
  }

  /// Сдвигает додзё по цепочке. Первое (стартовое) место зафиксировано.
  void moveDojo(String pageAction, int delta) {
    final list = dojos();
    final i = list.indexWhere((d) => d.pageAction == pageAction);
    final j = i + delta;
    if (i < 1 || j < 1 || j >= list.length) return;
    final t = list[i];
    list[i] = list[j];
    list[j] = t;
    _mutate(() => _relinkChain(list));
  }

  List<DiagIssue> dojoDiagnostics() {
    final out = <DiagIssue>[];
    final list = dojos();
    if (list.isEmpty) out.add(const DiagIssue(false, 'diag.dojoNone'));

    final pageIds = list.map((d) => d.pageAction).toSet();
    final loaders = <String, int>{};

    for (final d in list) {
      final t = d.title;
      if (d.loadAction.isEmpty) {
        out.add(DiagIssue(true, 'diag.dojoNoSelect', {'title': t}));
      } else if (d.load == null) {
        out.add(DiagIssue(true, 'diag.dojoNoLoad',
            {'title': t, 'action': d.loadAction}));
      }
      if (d.load != null) {
        if (d.location.isEmpty) {
          out.add(DiagIssue(true, 'diag.dojoNoLocation', {'title': t}));
        }
        if (d.loader.isEmpty) {
          out.add(DiagIssue(false, 'diag.dojoNoLoaderSet', {'title': t}));
        }
      }
      if (d.loader.isNotEmpty) {
        loaders[d.loader] = (loaders[d.loader] ?? 0) + 1;
        final si = d.startupIf;
        if (si == null) {
          if (d.loader != 'Default') {
            out.add(DiagIssue(false, 'diag.dojoNoStartup',
                {'title': t, 'loader': d.loader}));
          }
        } else {
          final startLoc = si.deep('ChangeDojoLocation')?.attr('Name') ?? '';
          if (startLoc != d.location) {
            out.add(DiagIssue(false, 'diag.dojoLocMismatch',
                {'title': t, 'start': startLoc, 'loc': d.location}));
          }
        }
      }
      if (!d.linked) {
        out.add(DiagIssue(false, 'diag.dojoUnlinked', {'title': t}));
      }

      final dialog = _dialogOf(d.page);
      if (dialog != null) {
        for (final type in const ['Right', 'Left']) {
          final target = _buttonTarget(dialog, type);
          if (target != null && !pageIds.contains(target)) {
            out.add(DiagIssue(true, 'diag.dojoBadTarget',
                {'title': t, 'type': type, 'target': target}));
          }
        }
      }
    }
    loaders.forEach((l, c) {
      if (c > 1) {
        out.add(DiagIssue(false, 'diag.dupLoader', {'loader': l, 'count': c}));
      }
    });
    return out;
  }
}