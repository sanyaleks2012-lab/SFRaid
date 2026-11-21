import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import 'config.dart';
import 'dojo_entry.dart';
import 'dojo_templates.dart';
import 'raid_io.dart';
import 'stats.dart';
import 'xml_helpers.dart';
import 'xml_kind.dart';

class RaidForgeController extends ChangeNotifier {
  String filePath;
  final RaidIo io;
  final XmlKind kind;

  late XmlDocument _doc;

  final List<XmlDocument> _undoStack = [];

  bool dirty = false;

  RaidForgeController(this.filePath, this.io, [this.kind = XmlKind.raid]);

  XmlElement get root => _doc.rootElement;

  int get undoCount => _undoStack.length;

  // ----------------------------------------------------------
  // LOAD
  // ----------------------------------------------------------

  Future<void> load() async {
  if (!await io.exists(filePath)) {
    throw RaidForgeException('Файл не найден:\n$filePath');
  }

  try {
    _doc = XmlDocument.parse(await io.read(filePath));
  } on XmlException catch (e) {
    throw RaidForgeException('XML повреждён:\n$e');
  } catch (e) {
    throw RaidForgeException('Ошибка чтения:\n$e');
  }

  _undoStack.clear();
  dirty = false;

  notifyListeners();
}

  // ----------------------------------------------------------
  // UNDO
  // ----------------------------------------------------------

  void _snapshot() {
    _undoStack.add(_doc.copy());

    if (_undoStack.length > maxUndo) {
      _undoStack.removeAt(0);
    }
  }

  void _mutate(void Function() action) {
    _snapshot();

    action();

    dirty = true;

    notifyListeners();
  }

  bool undo() {
    if (_undoStack.isEmpty) return false;

    _doc = _undoStack.removeLast();

    dirty = true;

    notifyListeners();

    return true;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  // ----------------------------------------------------------
  // SAVE
  // ----------------------------------------------------------

  Future<String?> save() async {
  if (!dirty) return null;

  final n = DateTime.now();

  final ts = '${n.year}${_two(n.month)}${_two(n.day)}_'
      '${_two(n.hour)}${_two(n.minute)}${_two(n.second)}';

  final backup = '$filePath.$ts.bak';

  if (!await io.exists(filePath)) {
    throw RaidForgeException(
      'Исходный файл больше не существует.',
    );
  }

  // Создаём резервную копию через выбранный способ доступа.
  await io.copy(filePath, backup);

  final xml = _doc.toXmlString(
    pretty: true,
    indent: '  ',
  );

  final out = xml.trimLeft().startsWith('<?xml')
      ? xml
      : '<?xml version="1.0" encoding="utf-8"?>\n$xml';

  // Запись через RaidIo, включая режим Shizuku.
  await io.write(filePath, out);

  dirty = false;
  notifyListeners();

  return backup;
}

  // ----------------------------------------------------------
  // TREE
  // ----------------------------------------------------------

  List<XmlElement> zones() {
    final node = root.kid('Zones');

    if (node != null) {
      return node.kids('Zone').toList();
    }

    return root.findAllElements('Zone').toList();
  }

  List<BattleRef> battles() {
    final result = <BattleRef>[];

    for (final z in zones()) {
      for (final b in z.kids('Battle')) {
        result.add((z, b));
      }
    }

    return result;
  }

  XmlElement? getWarrior(XmlElement battle) =>
      battle.deep('Warrior');

  XmlElement? getFight(XmlElement battle) =>
      battle.deep('Fight');

  XmlElement? getRules(XmlElement battle) =>
      getFight(battle)?.kid('Rules');

  // ----------------------------------------------------------
  // STATISTICS
  // ----------------------------------------------------------

  Stats statistics() {
    final s = Stats();

    if (kind.isQuests) {
      s.quests = quests().length;
      s.dojos = dojos().length;
      s.includes = root.kids('Include').length;
      return s;
    }

    final zs = zones();

    s.zones = zs.length;

    for (final zone in zs) {
      for (final battle in zone.kids('Battle')) {
        s.battles++;

        final warriors = battle.findAllElements('Warrior').toList();

        s.warriors += warriors.length;

        for (final w in warriors) {
          for (final perks in w.kids('Perks')) {
            s.warriorPerks += perks.kids('Perk').length;
          }
        }

        for (final rules in battle.findAllElements('Rules')) {
          s.complexRules += rules.kids('ComplexRule').length;
          s.equipItems += rules.kids('EquipItem').length;
          s.rulePerks += rules.kids('Perk').length;
        }

        s.currencies += battle.findAllElements('Currency').length;

        for (final rwc in battle.findAllElements('RulesWithConditions')) {
          for (final c in rwc.kids('Conditions')) {
            s.conditions += c.childElements.length;
          }
        }
      }
    }

    return s;
  }

  // ----------------------------------------------------------
  // ZONES
  // ----------------------------------------------------------

  void createZone(String name, String fileName) {
    _mutate(() {
      var zonesNode = root.kid('Zones');

      if (zonesNode == null) {
        zonesNode = makeEl('Zones');
        root.children.add(zonesNode);
      }

      zonesNode.children.add(
        makeEl('Zone', {
          'Name': name,
          'FileName': fileName,
        }),
      );
    });
  }

  void editZone(
    XmlElement zone,
    String name,
    String fileName,
  ) {
    if (name == zone.attr('Name') &&
        fileName == zone.attr('FileName')) {
      return;
    }

    _mutate(() {
      zone.put('Name', name);
      zone.put('FileName', fileName);
    });
  }

  void deleteZone(XmlElement zone) {
    _mutate(() => zone.remove());
  }

  // ----------------------------------------------------------
  // BATTLES
  // ----------------------------------------------------------

  void deleteBattle(XmlElement battle) {
    _mutate(() => battle.remove());
  }

  void duplicateBattle(
    XmlElement zone,
    XmlElement battle, [
    String? newName,
  ]) {
    _mutate(() {
      final clone = battle.copy();

      final old = clone.attr('Name', 'BOSS');

      clone.put(
        'Name',
        (newName == null || newName.isEmpty)
            ? '${old}_COPY'
            : newName,
      );

      zone.children.add(clone);
    });
  }

  void cloneBattleToZone(
    XmlElement template,
    XmlElement targetZone, [
    String? newName,
  ]) {
    _mutate(() {
      final clone = template.copy();

      final cur = clone.attr('Name', 'BOSS');

      clone.put(
        'Name',
        (newName == null || newName.isEmpty)
            ? '${cur}_COPY'
            : newName,
      );

      targetZone.children.add(clone);
    });
  }

  List<BattleRef> searchBosses(String query) {
    final q = query.toLowerCase();

    if (q.isEmpty) return [];

    final matches = <BattleRef>[];

    for (final (zone, battle) in battles()) {
      final warrior = getWarrior(battle);

      final values = <String>[
        battle.attr('Name'),
        battle.attr('Alias'),
        battle.attr('Title'),
        battle.attr('Location'),
        if (warrior != null) warrior.attr('Template'),
        if (warrior != null) warrior.attr('Tactic'),
      ];

      if (values.any((v) => v.toLowerCase().contains(q))) {
        matches.add((zone, battle));
      }
    }

    return matches;
  }

  // ----------------------------------------------------------
  // BOSS EDITS
  // ----------------------------------------------------------

  void editBossIdentity(
    XmlElement battle,
    String name,
    String title,
  ) {
    if (name == battle.attr('Name') &&
        title == battle.attr('Title')) {
      return;
    }

    _mutate(() {
      battle.put('Name', name);
      battle.put('Title', title);
    });
  }

  void editPowerShields(
    XmlElement warrior,
    String power,
    String shields,
  ) {
    if (power == warrior.attr('WarriorPower', '0') &&
        shields == warrior.attr('ShieldTotal', '0')) {
      return;
    }

    _mutate(() {
      warrior.put('WarriorPower', power);
      warrior.put('ShieldTotal', shields);
    });
  }

  void editRounds(
    XmlElement fight,
    String rounds,
    String roundTime,
  ) {
    if (rounds == fight.attr('Rounds', '0') &&
        roundTime == fight.attr('RoundTime', '999')) {
      return;
    }

    _mutate(() {
      fight.put('Rounds', rounds);
      fight.put('RoundTime', roundTime);
    });
  }

  // ----------------------------------------------------------
  // GENERIC ATTRIBUTES
  // ----------------------------------------------------------

  void setAttr(
    XmlElement el,
    String key,
    String value,
  ) {
    _mutate(() => el.put(key, value));
  }

  void changeAttr(
    XmlElement el,
    String key,
    String value,
  ) {
    if (value == el.attr(key)) return;

    setAttr(el, key, value);
  }

  void removeAttr(XmlElement el, String key) {
    _mutate(() => el.removeAttribute(key));
  }

  XmlElement addChild(
    XmlElement parent,
    String tag, [
    Map<String, String> attrs = const {},
  ]) {
    final child = makeEl(tag, attrs);

    _mutate(() => parent.children.add(child));

    return child;
  }

  void removeChild(XmlElement child) {
    _mutate(() => child.remove());
  }

  // ----------------------------------------------------------
  // PERKS
  // ----------------------------------------------------------

  XmlElement ensurePerks(XmlElement warrior) {
    var perks = warrior.kid('Perks');

    if (perks == null) {
      perks = makeEl('Perks');

      final p = perks;

      _mutate(() => warrior.children.add(p));
    }

    return perks;
  }

  void addPresetPerk(
    XmlElement perksNode,
    String presetKey,
  ) {
    final preset = presetPerks[presetKey];

    if (preset == null) return;

    final (_, name, attrs) = preset;

    _mutate(() {
      final perk = makeEl('Perk', {'Name': name});

      if (attrs.isNotEmpty) {
        perk.children.add(makeEl('Set', attrs));
      }

      perksNode.children.add(perk);
    });
  }

  void addCustomPerk(
    XmlElement parent,
    String name, {
    Map<String, String>? setAttrs,
    String? applyTo,
  }) {
    _mutate(() {
      final perk = makeEl('Perk', {
        'Name': name,
        if (applyTo != null) 'ApplyTo': applyTo,
      });

      if (setAttrs != null) {
        perk.children.add(makeEl('Set', setAttrs));
      }

      parent.children.add(perk);
    });
  }

  void editPerk(
    XmlElement perk, {
    String? name,
    String? applyTo,
  }) {
    final newName = name;

    final newApplyTo = applyTo;

    final nameChanged = newName != null &&
        newName.isNotEmpty &&
        newName != perk.attr('Name');

    final applyChanged = newApplyTo != null &&
        newApplyTo != perk.attr('ApplyTo');

    if (!nameChanged && !applyChanged) return;

    _mutate(() {
      if (nameChanged) {
        perk.put('Name', newName!);
      }

      if (applyChanged) {
        if (newApplyTo!.isEmpty) {
          perk.removeAttribute('ApplyTo');
        } else {
          perk.put('ApplyTo', newApplyTo);
        }
      }
    });
  }

  XmlElement ensureSetNode(XmlElement perk) {
    var set = perk.kid('Set');

    if (set == null) {
      set = makeEl('Set');

      final s = set;

      _mutate(() => perk.children.add(s));
    }

    return set;
  }

  // ----------------------------------------------------------
  // RULES
  // ----------------------------------------------------------

  XmlElement? ensureRules(XmlElement battle) {
    final fight = getFight(battle);

    if (fight == null) return null;

    var rules = fight.kid('Rules');

    if (rules == null) {
      rules = makeEl('Rules');

      final r = rules;

      _mutate(() => fight.children.add(r));
    }

    return rules;
  }

  void editAvatarName(
    XmlElement rules,
    String newAvatar,
    String newName,
  ) {
    final avatar = rules.kid('Avatar');

    final charName = rules.kid('Name');

    if (newAvatar == (avatar?.attr('Name') ?? '') &&
        newName == (charName?.attr('Name') ?? '')) {
      return;
    }

    _mutate(() {
      var a = avatar;

      if (newAvatar.isNotEmpty) {
        if (a == null) {
          a = makeEl('Avatar');
          rules.children.insert(0, a);
        }

        a.put('Name', newAvatar);
      } else if (a != null) {
        a.remove();
        a = null;
      }

      var n = charName;

      if (newName.isNotEmpty) {
        if (n == null) {
          n = makeEl('Name');

          final idx = a != null
              ? rules.children.indexOf(a) + 1
              : 0;

          rules.children.insert(idx, n);
        }

        n.put('Name', newName);
      } else if (n != null) {
        n.remove();
      }
    });
  }

  void addEquipItem(
    XmlElement rules,
    String name, [
    String applyTo = 'Player',
  ]) {
    _mutate(() {
      rules.children.add(
        makeEl('EquipItem', {
          'Name': name,
          'ApplyTo': applyTo,
        }),
      );
    });
  }

  void editEquipItem(
    XmlElement item,
    String name,
    String applyTo,
  ) {
    if (name == item.attr('Name') &&
        applyTo == item.attr('ApplyTo', 'Player')) {
      return;
    }

    _mutate(() {
      item.put('Name', name);

      if (applyTo.isNotEmpty) {
        item.put('ApplyTo', applyTo);
      } else {
        item.removeAttribute('ApplyTo');
      }
    });
  }

  void quickEquipment(
    XmlElement rules,
    String itemsLine, [
    String applyTo = 'Player',
  ]) {
    final names = itemsLine
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    if (names.isEmpty) return;

    _mutate(() {
      for (final n in names) {
        rules.children.add(
          makeEl('EquipItem', {
            'Name': n,
            'ApplyTo': applyTo,
          }),
        );
      }
    });
  }

  void addComplexRulePreset(
    XmlElement rules,
    String presetKey,
  ) {
    final preset = presetRules[presetKey];

    if (preset == null) return;

    final (_, alias, tag, attrs) = preset;

    _mutate(() {
      final cr = makeEl('ComplexRule');

      cr.children.add(
        makeEl('Description', {'Alias': alias}),
      );

      cr.children.add(makeEl(tag, attrs));

      rules.children.add(cr);
    });
  }

  void setComplexRuleAlias(
    XmlElement rule,
    String alias,
  ) {
    _mutate(() {
      var desc = rule.kid('Description');

      if (desc == null) {
        desc = makeEl('Description');
        rule.children.insert(0, desc);
      }

      desc.put('Alias', alias);
    });
  }

  List<XmlElement> complexRuleChildren(XmlElement rule) {
    return rule.childElements
        .where((e) => e.name.local != 'Description')
        .toList();
  }

  XmlElement createRulesWithConditions(XmlElement rules) {
    final wrapper = makeEl('RulesWithConditions')
      ..children.add(makeEl('Conditions'))
      ..children.add(makeEl('RuleList'));

    _mutate(() => rules.children.add(wrapper));

    return wrapper;
  }

  XmlElement ensureConditions(XmlElement wrapper) {
    var c = wrapper.kid('Conditions');

    if (c == null) {
      c = makeEl('Conditions');

      final x = c;

      _mutate(() => wrapper.children.add(x));
    }

    return c;
  }

  XmlElement ensureRuleList(XmlElement wrapper) {
    var r = wrapper.kid('RuleList');

    if (r == null) {
      r = makeEl('RuleList');

      final x = r;

      _mutate(() => wrapper.children.add(x));
    }

    return r;
  }

  void clearUserRules(XmlElement rules) {
    _mutate(() {
      for (final child in rules.childElements.toList()) {
        if (removableRuleTags.contains(child.name.local)) {
          child.remove();
        }
      }
    });
  }

  // ----------------------------------------------------------
  // REWARDS
  // ----------------------------------------------------------

  XmlElement createReward(XmlElement battle) {
    final r = makeEl('Reward');

    _mutate(() => battle.children.add(r));

    return r;
  }

  void editReward(
    XmlElement reward, {
    required String prizeBase,
    required String exp,
    required String bonus,
  }) {
    _mutate(() {
      reward.put('PrizeBase', prizeBase);
      reward.put('Exp', exp);
      reward.put('Bonus', bonus);
    });
  }

  void addCurrency(
    XmlElement reward,
    String name, [
    String expectedValue = '0',
  ]) {
    _mutate(() {
      reward.children.add(
        makeEl('Currency', {
          'Name': name,
          'ExpectedValue': expectedValue,
        }),
      );
    });
  }

  void editCurrency(
    XmlElement currency,
    String name,
    String expectedValue,
  ) {
    _mutate(() {
      currency.put('Name', name);
      currency.put('ExpectedValue', expectedValue);
    });
  }

  String elementToXml(XmlElement el) {
    return el.toXmlString(pretty: true, indent: '  ');
  }

  // ----------------------------------------------------------
  // QUESTS: GENERIC
  // ----------------------------------------------------------

  List<XmlElement> quests() => root.kids('Quest').toList();

  XmlElement addQuest(String name, String event) {
    final q = makeEl('Quest', {'Name': name});

    final events = makeEl('Events')..children.add(makeEl(event));

    q.children.add(events);
    q.children.add(makeEl('Actions'));

    _mutate(() => root.children.add(q));

    return q;
  }

  void duplicateRootElement(XmlElement el, String newName) {
    final parent = el.parent;

    if (parent == null) return;

    _mutate(() {
      final clone = el.copy();

      if (newName.isNotEmpty) clone.put('Name', newName);

      parent.children.insert(parent.children.indexOf(el) + 1, clone);
    });
  }

  /// Заменяет элемент на разобранный из текста XML.
  void replaceElementXml(XmlElement old, String xml) {
    final fresh = parseFragment(xml);

    final parent = old.parent;

    if (parent == null) {
      throw RaidForgeException('Элемент уже не принадлежит документу.');
    }

    _mutate(() {
      parent.children.insert(parent.children.indexOf(old), fresh);
      old.remove();
    });
  }

  // ----------------------------------------------------------
  // QUESTS: DOJO CHANGER
  // ----------------------------------------------------------

  static const String _actionIdVar = r'_$ActionID';
  static const String _dojoTitle = 'DojoChangerTitle';
  static const String _startupQuest = 'DojoChanger_LoadSelectedDojo';

  String? _actionCond(XmlElement quest) {
    final conds = quest.kid('Conditions');

    if (conds == null) return null;

    for (final e in conds.kids('Equal')) {
      if (e.attr('Value1') == _actionIdVar) return e.attr('Value2');
    }

    return null;
  }

  bool _onActivate(XmlElement q) => q.kid('Events')?.kid('Activate') != null;

  XmlElement? _dialog(XmlElement page) => page.kid('Actions')?.kid('Dialog');

  XmlElement? _button(XmlElement dialog, String type) => dialog
      .kids('Button')
      .where((b) => b.attr('Type') == type)
      .firstOrNull;

  String? _buttonTarget(XmlElement dialog, String type) =>
      _button(dialog, type)?.kid('Activate')?.attr('ActionID');

  void _setButtonTarget(XmlElement dialog, String type, String? target) {
    final btn = _button(dialog, type);

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

  XmlElement? _startupIf(String loader) {
    for (final i in root.findAllElements('If')) {
      final conds = i.kid('Conditions');

      if (conds == null) continue;

      for (final e in conds.kids('Equal')) {
        if (e.attr('Value1') == '_DojoLoader' &&
            e.attr('Value2') == loader) {
          return i;
        }
      }
    }

    return null;
  }

  /// Додзё в порядке листания: DefaultPage → NEXT → NEXT ...
  /// Недостижимые страницы идут в конце.
  List<DojoEntry> dojos() {
    final pages = <String, XmlElement>{};
    final loads = <String, XmlElement>{};

    for (final q in quests()) {
      if (!_onActivate(q)) continue;

      final id = _actionCond(q);

      if (id == null) continue;

      final dialog = _dialog(q);

      if (dialog != null && dialog.attr('Title') == _dojoTitle) {
        pages.putIfAbsent(id, () => q);
      } else if (q.kid('Actions')?.kid('ChangeDojoLocation') != null) {
        loads.putIfAbsent(id, () => q);
      }
    }

    final order = <String>[];

    String? cur =
        pages.containsKey('DefaultPage') ? 'DefaultPage' : pages.keys.firstOrNull;

    while (cur != null && pages.containsKey(cur) && !order.contains(cur)) {
      order.add(cur);
      cur = _buttonTarget(_dialog(pages[cur]!)!, 'Right');
    }

    final linked = order.toSet();

    for (final k in pages.keys) {
      if (!linked.contains(k)) order.add(k);
    }

    final result = <DojoEntry>[];

    for (final pa in order) {
      final page = pages[pa]!;
      final dialog = _dialog(page)!;
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

      result.add(
        DojoEntry(
          page: page,
          load: load,
          startupIf: loader.isEmpty ? null : _startupIf(loader),
          pageAction: pa,
          loadAction: loadAction,
          labelKey: dialog.kid('Line')?.attr('Text') ?? '',
          location: actions?.kid('ChangeDojoLocation')?.attr('Name') ?? '',
          loader: loader,
          linked: linked.contains(pa),
        ),
      );
    }

    return result;
  }

  /// Перепривязывает NEXT / BACK по заданному порядку.
  /// Первая страница: BACK просто закрывает диалог.
  /// Последняя страница: NEXT возвращает на первую.
  void _relinkChain(List<DojoEntry> order) {
    for (var i = 0; i < order.length; i++) {
      final dialog = _dialog(order[i].page);

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
    var q = quests()
        .where((x) => x.attr('Name') == _startupQuest)
        .firstOrNull;

    if (q == null) {
      final nq = parseFragment(dojoStartupQuestTemplate);
      root.children.add(nq);
      q = nq;
    }

    var actions = q.kid('Actions');

    if (actions == null) {
      final na = makeEl('Actions');
      q.children.add(na);
      actions = na;
    }

    final iff = parseFragment(dojoStartupIfTemplate);

    iff.kid('Conditions')!.kid('Equal')!.put('Value2', loader);
    iff.kid('Then')!.kid('ChangeDojoLocation')!.put('Name', location);

    actions.children.add(iff);
  }

  /// Создаёт Page + Load + стартовую загрузку и добавляет додзё
  /// в конец цепочки листания.
  void addDojo({
    required String id,
    required String location,
    String labelKey = '',
    String loader = '',
  }) {
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(id)) {
      throw RaidForgeException('Id: только латиница, цифры и «_».');
    }

    if (location.isEmpty) {
      throw RaidForgeException('Location (имя локации додзё) не задан.');
    }

    final pageAction = '${id}Page';
    final loadAction = 'Dojo$id';
    final label = labelKey.isEmpty ? 'Dojo$id' : labelKey;
    final loaderValue = loader.isEmpty ? id : loader;

    final existing = dojos();

    if (existing.any(
      (d) => d.pageAction == pageAction || d.loadAction == loadAction,
    )) {
      throw RaidForgeException('Додзё с Id «$id» уже есть.');
    }

    if (existing.any((d) => d.loader == loaderValue)) {
      throw RaidForgeException('DojoLoader «$loaderValue» уже занят.');
    }

    final pageName = 'Dojo${id}_Page';
    final loadName = 'Dojo${id}_Load';

    if (quests().any(
      (q) => q.attr('Name') == pageName || q.attr('Name') == loadName,
    )) {
      throw RaidForgeException('Квест $pageName / $loadName уже существует.');
    }

    _mutate(() {
      final page = parseFragment(dojoPageTemplate);

      page.put('Name', pageName);
      page.kid('Conditions')!.kid('Equal')!.put('Value2', pageAction);

      final dialog = page.kid('Actions')!.kid('Dialog')!;

      dialog.kid('Line')!.put('Text', label);

      _setButtonTarget(dialog, 'Middle', loadAction);

      final load = parseFragment(dojoLoadTemplate);

      load.put('Name', loadName);
      load.kid('Conditions')!.kid('Equal')!.put('Value2', loadAction);

      final la = load.kid('Actions')!;

      la.kid('ChangeDojoLocation')!.put('Name', location);
      la.kid('SetVariable')!.put('Value', loaderValue);

      root.children.add(page);
      root.children.add(load);

      _addStartup(loaderValue, location);

      // Новая страница недостижима, поэтому dojos() ставит её последней.
      _relinkChain(dojos());
    });
  }

  void editDojo(
    String pageAction, {
    String? labelKey,
    String? location,
    String? loader,
  }) {
    final e = dojos().where((d) => d.pageAction == pageAction).firstOrNull;

    if (e == null) throw RaidForgeException('Додзё не найдено.');

    if (labelKey != null && labelKey.isEmpty) {
      throw RaidForgeException('Текст (Line Text) не может быть пустым.');
    }

    if (location != null && location.isEmpty) {
      throw RaidForgeException('Location не может быть пустым.');
    }

    if (loader != null) {
      if (loader.isEmpty) {
        throw RaidForgeException('DojoLoader не может быть пустым.');
      }

      if (dojos().any(
        (d) => d.pageAction != pageAction && d.loader == loader,
      )) {
        throw RaidForgeException('DojoLoader «$loader» уже занят.');
      }
    }

    final changed = (labelKey != null && labelKey != e.labelKey) ||
        (location != null && location != e.location) ||
        (loader != null && loader != e.loader);

    if (!changed) return;

    _mutate(() {
      if (labelKey != null) {
        _dialog(e.page)?.kid('Line')?.put('Text', labelKey);
      }

      if (location != null) {
        e.load?.kid('Actions')?.kid('ChangeDojoLocation')?.put(
              'Name',
              location,
            );

        final si = e.startupIf;

        if (si != null) {
          for (final c in si.findAllElements('ChangeDojoLocation')) {
            c.put('Name', location);
          }
        }
      }

      if (loader != null) {
        final la = e.load?.kid('Actions');

        if (la != null) {
          for (final s in la.kids('SetVariable')) {
            if (s.attr('Name') == 'DojoLoader') s.put('Value', loader);
          }
        }

        final conds = e.startupIf?.kid('Conditions');

        if (conds != null) {
          for (final c in conds.kids('Equal')) {
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
      throw RaidForgeException('Первое (стартовое) додзё удалить нельзя.');
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

      // Отдельный стартовый квест без действий больше не нужен.
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

  DiagnosticsResult _questDiagnostics() {
    final errors = <String>[];
    final warnings = <String>[];

    final names = <String, int>{};

    for (final q in quests()) {
      final n = q.attr('Name');

      if (n.isEmpty) {
        errors.add('Quest без Name.');
        continue;
      }

      names[n] = (names[n] ?? 0) + 1;
    }

    names.forEach((n, c) {
      if (c > 1) warnings.add('Дубликат Quest Name: $n (×$c).');
    });

    final list = dojos();

    if (list.isEmpty) {
      warnings.add('Dojo Changer: страницы выбора додзё не найдены.');
    }

    final pageIds = list.map((d) => d.pageAction).toSet();
    final loaders = <String, int>{};

    for (final d in list) {
      final t = d.title;

      if (d.loadAction.isEmpty) {
        errors.add('$t: у кнопки SELECT нет Activate ActionID.');
      } else if (d.load == null) {
        errors.add('$t: нет Load-квеста для ActionID «${d.loadAction}».');
      }

      if (d.load != null) {
        if (d.location.isEmpty) errors.add('$t: нет ChangeDojoLocation.');

        if (d.loader.isEmpty) {
          warnings.add('$t: Load-квест не ставит DojoLoader.');
        }
      }

      if (d.loader.isNotEmpty) {
        loaders[d.loader] = (loaders[d.loader] ?? 0) + 1;

        final si = d.startupIf;

        if (si == null) {
          if (d.loader != 'Default') {
            warnings.add(
              '$t: нет стартовой загрузки (If _DojoLoader = ${d.loader}) — '
              'выбор не восстановится после перезапуска.',
            );
          }
        } else {
          final startLoc =
              si.deep('ChangeDojoLocation')?.attr('Name') ?? '';

          if (startLoc != d.location) {
            warnings.add(
              '$t: локация при старте («$startLoc») не совпадает '
              'с Load-квестом («${d.location}»).',
            );
          }
        }
      }

      if (!d.linked) {
        warnings.add('$t: страница недостижима по цепочке NEXT.');
      }

      final dialog = _dialog(d.page);

      if (dialog != null) {
        for (final type in const ['Right', 'Left']) {
          final target = _buttonTarget(dialog, type);

          if (target != null && !pageIds.contains(target)) {
            errors.add(
              '$t: кнопка $type ведёт на несуществующую '
              'страницу «$target».',
            );
          }
        }
      }
    }

    loaders.forEach((l, c) {
      if (c > 1) warnings.add('DojoLoader «$l» используется $c раз(а).');
    });

    return DiagnosticsResult(errors, warnings, statistics());
  }

  // ----------------------------------------------------------
  // DIAGNOSTICS
  // ----------------------------------------------------------

  DiagnosticsResult diagnostics() {
    if (kind.isQuests) return _questDiagnostics();

    final errors = <String>[];

    final warnings = <String>[];

    final zs = zones();

    if (zs.isEmpty) {
      warnings.add('Zones отсутствует или пуст.');
    }

    for (final zone in zs) {
      if (zone.attr('Name').isEmpty) {
        warnings.add('Zone без Name.');
      }

      for (final battle in zone.kids('Battle')) {
        final bn = battle.attr('Name', '?');

        if (battle.attr('Name').isEmpty) {
          warnings.add('Battle без Name.');
        }

        if (getWarrior(battle) == null) {
          warnings.add('$bn: нет Warrior.');
        }

        if (getFight(battle) == null) {
          warnings.add('$bn: нет Fight.');
        }

        final rules = getRules(battle);

        if (rules != null) {
          for (final item in rules.kids('EquipItem')) {
            if (item.attr('Name').isEmpty) {
              errors.add('$bn: EquipItem без Name.');
            }
          }

          for (final perk in rules.kids('Perk')) {
            if (perk.attr('Name').isEmpty) {
              errors.add('$bn: Rule-Perk без Name.');
            }
          }
        }
      }
    }

    return DiagnosticsResult(errors, warnings, statistics());
  }
}
