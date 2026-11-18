import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xml/xml.dart';
import 'package:file_picker/file_picker.dart';
import 'shizuku_bridge.dart';

// ============================================================
// STORAGE
// ============================================================

Future<bool> requestStoragePermission() async {
  if (!Platform.isAndroid) return true;

  try {
    var status = await Permission.manageExternalStorage.status;

    if (status.isGranted) return true;

    status = await Permission.manageExternalStorage.request();

    return status.isGranted;
  } catch (_) {
    return false;
  }
}

// ============================================================
// CONFIG / PRESETS
// ============================================================

const int maxUndo = 30;

const String defaultFilePath =
    '/storage/emulated/0/raid_stages_default.xml';

const Map<String, (String, String, Map<String, String>)> presetPerks = {
  '1': ('OVERHEAT', 'PERK_ITEM_SPECIAL_OVERHEAT_WEAPON', {
    'Aspect': '100000',
    'Frames': '300'
  }),
  '2': ('BLEEDING', 'PERK_ITEM_SPECIAL_BLEEDING_WEAPON', {
    'Aspect': '100000'
  }),
  '3': ('DAMAGE ABSORPTION',
      'PERK_ITEM_SPECIAL_DAMAGE_ABSORBPTION_BODY_ARMOR', {
    'Aspect': '100000',
    'Chance': '0.2'
  }),
  '4': ('INVISIBILITY', 'PERK_INVISIBILITY', {'Frames': '600'}),
  '5': ('BLOCK BREAKER', 'PERK_BLOCK_BREAKER', {'Chance': '0.33'}),
  '6': ('PAIN RAGE', 'PERK_PAIN_RAGE', {
    'Chance': '0.25',
    'DamageFactor': '3000'
  }),
  '7': ('PLOT TWIST', 'PERK_PLOT_TWIST', {
    'Chance': '1.0',
    'Type': 'CopyMagic'
  }),
  '8': ('SOUL TYPHOON', 'PERK_SOUL_TYPHOON', {'Aspect': '100000'}),
  '9': ('TIME SHIFT', 'PERK_TIME_SHIFT', {'Frames': '300'}),
  '10': ('CRIMSON CORRUPTION', 'PERK_CRIMSON_CORRUPTION', {
    'Aspect': '100000'
  }),
  '11': ('ROARING LIGHT', 'PERK_ROARING_LIGHT', {'Aspect': '100000'}),
};

const Map<String, (String, String, String, Map<String, String>)> presetRules = {
  '1': ('HOT GROUND', 'HOT_GROUND', 'HotGround', {
    'Frames': '720',
    'ApplyTo': 'Player'
  }),
  '2': ('INVERTED JOYSTICK', 'INVERTED_JOYSTICK', 'InvertJoystick', {}),
  '3': ('NO HEALTH BAR', 'NO_HEALTHBAR', 'NoHealthBar', {}),
  '4': ('NO JUMPS', 'NO_JUMPS', 'NoAnimation', {'Name': 'Jump'}),
  '5': ('NO KICKS', 'NO_KICKS', 'NoButton', {
    'Name': 'Kick',
    'ApplyTo': 'Player'
  }),
  '6': ('NO BLOCKS', 'NO_BLOCKS', 'RemoveInterval', {
    'Type': 'Block',
    'ApplyTo': 'Player'
  }),
};

const Set<String> removableRuleTags = {
  'Avatar',
  'Name',
  'EquipItem',
  'Perk',
  'ComplexRule',
  'RulesWithConditions',
};

// ============================================================
// SUPPORTED FILES (только эти 3 файла можно загрузить)
// ============================================================

enum XmlKind {
  raid('raid_stages_default.xml', 'Raid stages'),
  quests('quests.xml', 'Quests'),
  stages('stages.xml', 'Stages');

  final String fileName;
  final String title;

  const XmlKind(this.fileName, this.title);

  bool get isQuests => this == XmlKind.quests;

  /// Определяет тип по имени файла (строгое совпадение).
  static XmlKind? fromPath(String path) {
    final base = path.split(RegExp(r'[\\/]')).last.trim().toLowerCase();

    for (final k in XmlKind.values) {
      if (k.fileName == base) return k;
    }

    return null;
  }

  static String get allowedList =>
      XmlKind.values.map((k) => k.fileName).join(', ');
}

// ============================================================
// XML HELPERS
// ============================================================

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class RaidForgeException implements Exception {
  final String message;

  RaidForgeException(this.message);

  @override
  String toString() => message;
}

XmlElement makeEl(
  String tag, [
  Map<String, String> attrs = const {},
]) {
  return XmlElement(
    XmlName(tag),
    attrs.entries.map(
      (e) => XmlAttribute(XmlName(e.key), e.value),
    ),
  );
}

extension RaidXml on XmlElement {
  String attr(String name, [String def = '']) =>
      getAttribute(name) ?? def;

  Iterable<XmlElement> kids(String tag) => findElements(tag);

  XmlElement? kid(String tag) => findElements(tag).firstOrNull;

  XmlElement? deep(String tag) => findAllElements(tag).firstOrNull;

  void put(String name, String value) => setAttribute(name, value);

  Map<String, String> get attrMap => {
        for (final a in attributes) a.name.local: a.value,
      };
}

typedef BattleRef = (XmlElement zone, XmlElement battle);

// ============================================================
// STATISTICS
// ============================================================

class Stats {
  int zones = 0,
      battles = 0,
      warriors = 0,
      warriorPerks = 0,
      complexRules = 0,
      equipItems = 0,
      rulePerks = 0,
      currencies = 0,
      conditions = 0,
      quests = 0,
      dojos = 0,
      includes = 0;
}

class DiagnosticsResult {
  final List<String> errors;
  final List<String> warnings;
  final Stats stats;

  DiagnosticsResult(this.errors, this.warnings, this.stats);
}

// ============================================================
// QUESTS: DOJO MODEL / TEMPLATES
// ============================================================

/// Одно додзё в «Dojo Changer» из quests.xml.
///
/// Логика файла:
///  • Page-квест  (Events/Activate, Dialog Title="DojoChangerTitle") —
///    страница листалки: кнопки NEXT / SELECT / BACK, текст Line.
///  • Load-квест  (Events/Activate, ChangeDojoLocation) — срабатывает по
///    SELECT: ставит DojoLoader, меняет локацию, ChangeScene в Dojo.
///  • Стартовый If в DojoChanger_LoadSelectedDojo (или отдельном квесте)
///    восстанавливает выбранное додзё при запуске игры.
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

XmlElement parseFragment(String xml) {
  try {
    return XmlDocument.parse(xml).rootElement.copy();
  } on XmlException catch (e) {
    throw RaidForgeException('XML некорректен:\n$e');
  }
}

const String _dojoPageTemplate = r'''
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

const String _dojoLoadTemplate = r'''
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

const String _dojoStartupQuestTemplate = '''
<Quest Name="DojoChanger_LoadSelectedDojo" Priority="999">
  <Events>
    <ApplicationStart />
  </Events>
  <Actions />
</Quest>''';

const String _dojoStartupIfTemplate = '''
<If>
  <Conditions>
    <Equal Value1="_DojoLoader" Value2="" />
  </Conditions>
  <Then>
    <ChangeDojoLocation Name="" />
  </Then>
</If>''';

// ============================================================
// CONTROLLER
// ============================================================

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
      final nq = parseFragment(_dojoStartupQuestTemplate);
      root.children.add(nq);
      q = nq;
    }

    var actions = q.kid('Actions');

    if (actions == null) {
      final na = makeEl('Actions');
      q.children.add(na);
      actions = na;
    }

    final iff = parseFragment(_dojoStartupIfTemplate);

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

// ============================================================
// UI HELPERS
// ============================================================

late RaidForgeController ctrl;

void go(BuildContext c, Widget w) {
  Navigator.of(c).push(
    MaterialPageRoute(builder: (_) => w),
  );
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(
    SnackBar(content: Text(m)),
  );
}

Future<bool> confirm(BuildContext c, String msg) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (x) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(x, false),
          child: const Text('Нет'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(x, true),
          child: const Text('Да'),
        ),
      ],
    ),
  );

  return r ?? false;
}

Future<Map<String, String>?> form(
  BuildContext c,
  String title,
  Map<String, String> fields, {
  String hint = '',
}) {
  final ctrls = {
    for (final e in fields.entries)
      e.key: TextEditingController(text: e.value),
  };

  return showDialog<Map<String, String>>(
    context: c,
    builder: (x) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
            for (final e in ctrls.entries)
              TextField(
                controller: e.value,
                decoration: InputDecoration(labelText: e.key),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(x),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(x, {
            for (final e in ctrls.entries)
              e.key: e.value.text.trim(),
          }),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<int?> pick(
  BuildContext c,
  String title,
  List<String> items,
) {
  return showDialog<int>(
    context: c,
    builder: (x) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (_, i) => ListTile(
            dense: true,
            title: Text(items[i]),
            onTap: () => Navigator.pop(x, i),
          ),
        ),
      ),
    ),
  );
}

Widget tile(
  IconData icon,
  String title, {
  String? sub,
  VoidCallback? onTap,
  Widget? trailing,
}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: sub == null ? null : Text(sub),
    trailing: trailing ??
        (onTap != null ? const Icon(Icons.chevron_right) : null),
    onTap: onTap,
  );
}

Widget emptyNote(String text) {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey),
      ),
    ),
  );
}

Future<void> doSave(BuildContext context) async {
  if (!ctrl.dirty) {
    toast(context, 'Нет изменений для сохранения.');
    return;
  }

  try {
    final b = await ctrl.save();

    if (context.mounted) {
      toast(context, 'XML сохранён. Backup: $b');
    }
  } catch (e) {
    if (context.mounted) {
      toast(context, 'Ошибка сохранения: $e');
    }
  }
}

// ============================================================
// APP
// ============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const RaidForgeApp());
}

class RaidForgeApp extends StatelessWidget {
  const RaidForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SF2 Raid Forge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      builder: (context, child) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: child,
        ),
      ),
      home: const StartScreen(),
    );
  }
}

// ============================================================
// START SCREEN
// ============================================================

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

enum AccessMode { direct, shizuku }

class _StartScreenState extends State<StartScreen> {
  late final TextEditingController _path;
  final _pkg = TextEditingController(text: 'com.onerdna.sfml');

  AccessMode _mode = AccessMode.direct;
  ShizukuState _shz = ShizukuState.notInstalled;
  // Файлы, найденные в gamedata при последнем поиске (только 3 допустимых).
  Set<String> _found = {};
  String _xmlFile = XmlKind.raid.fileName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: defaultFilePath);
    _refreshShizuku();
  }

  @override
  void dispose() {
    _path.dispose();
    _pkg.dispose();
    super.dispose();
  }

  String get _pkgText => _pkg.text.trim();

  String get _resolvedPath => _mode == AccessMode.shizuku
      ? '${gamedataDir(_pkgText)}/$_xmlFile'
      : _path.text.trim();

  String get _shizukuLabel => switch (_shz) {
        ShizukuState.notInstalled => 'Shizuku не установлен',
        ShizukuState.notRunning => 'Shizuku не запущен',
        ShizukuState.noPermission => 'Нужно разрешение Shizuku',
        ShizukuState.ready => 'Shizuku готов',
      };

  Future<void> _refreshShizuku() async {
    final s = await ShizukuBridge.state();
    if (mounted) setState(() => _shz = s);
  }

  Future<bool> _ensureShizuku() async {
    await _refreshShizuku();
    if (_shz == ShizukuState.noPermission) {
      await ShizukuBridge.requestPermission();
      await _refreshShizuku();
    }
    if (_shz != ShizukuState.ready && mounted) {
      toast(context, '$_shizukuLabel. Запусти Shizuku и выдай доступ.');
    }
    return _shz == ShizukuState.ready;
  }

  Future<void> _scanFiles() async {
    if (!isValidPackage(_pkgText)) {
      toast(context, 'Некорректное имя пакета.');
      return;
    }
    if (!await _ensureShizuku()) return;
    try {
      final all = await ShizukuBridge.list(gamedataDir(_pkgText));
      final found = <String>{
        for (final k in XmlKind.values)
          if (all.contains(k.fileName)) k.fileName,
      };
      if (!mounted) return;
      setState(() {
        _found = found;
        if (found.isNotEmpty && !found.contains(_xmlFile)) {
          _xmlFile = found.contains(XmlKind.raid.fileName)
              ? XmlKind.raid.fileName
              : found.first;
        }
      });
      if (found.isEmpty) {
        toast(context, 'В gamedata нет файлов: ${XmlKind.allowedList}.');
      }
    } catch (e) {
      if (mounted) toast(context, 'Ошибка чтения папки: $e');
    }
  }

  Future<void> _requestPermission() async {
    final granted = await requestStoragePermission();
    if (!mounted) return;
    if (granted) {
      toast(context, 'Доступ ко всем файлам разрешён.');
    } else {
      toast(context, 'Разрешение не выдано. Проверь специальный доступ к файлам.');
      await openAppSettings();
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        allowMultiple: false,
      );
      if (!mounted || result == null) return;
      final selected = result.files.single.path;
      if (selected == null) {
        toast(context, 'Не удалось получить путь к файлу.');
        return;
      }
      if (XmlKind.fromPath(selected) == null) {
        toast(context, 'Можно открыть только: ${XmlKind.allowedList}.');
        return;
      }
      setState(() => _path.text = selected);
    } catch (e) {
      if (mounted) toast(context, 'Ошибка выбора файла: $e');
    }
  }

  /// Меняет имя файла в пути (папка остаётся прежней).
  void _setDirectFile(XmlKind k) {
    final p = _path.text.trim();
    final i = p.lastIndexOf('/');
    final dir = i > 0 ? p.substring(0, i) : '/storage/emulated/0';
    setState(() => _path.text = '$dir/${k.fileName}');
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final RaidIo io;
      if (_mode == AccessMode.shizuku) {
        if (!isValidPackage(_pkgText)) {
          toast(context, 'Некорректное имя пакета.');
          return;
        }
        if (!await _ensureShizuku()) return;
        io = ShizukuIo();
      } else {
        if (!await requestStoragePermission()) {
          if (!mounted) return;
          toast(context, 'Сначала разреши доступ ко всем файлам.');
          await openAppSettings();
          return;
        }
        io = DirectIo();
      }
      final path = _resolvedPath;
      if (path.isEmpty) {
        if (mounted) toast(context, 'Укажи путь к XML-файлу.');
        return;
      }
      final kind = XmlKind.fromPath(path);
      if (kind == null) {
        if (mounted) {
          toast(context, 'Можно открыть только: ${XmlKind.allowedList}.');
        }
        return;
      }
      final c = RaidForgeController(path, io, kind);
      await c.load();
      if (!mounted) {
        c.dispose();
        return;
      }
      ctrl = c;
      // quests.xml открывается в специальном редакторе квестов / додзё.
      go(
        context,
        kind.isQuests ? const QuestsHomeScreen() : const HomeScreen(),
      );
    } on RaidForgeException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shizuku = _mode == AccessMode.shizuku;
    return Scaffold(
      appBar: AppBar(title: const Text('SF2 • RAID FORGE')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<AccessMode>(
                    segments: const [
                      ButtonSegment(
                        value: AccessMode.direct,
                        icon: Icon(Icons.folder),
                        label: Text('Файлы'),
                      ),
                      ButtonSegment(
                        value: AccessMode.shizuku,
                        icon: Icon(Icons.adb),
                        label: Text('Shizuku'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() => _mode = s.first);
                      if (s.first == AccessMode.shizuku) _refreshShizuku();
                    },
                  ),
                  const SizedBox(height: 20),
                  if (!shizuku) ...[
                    TextField(
                      controller: _path,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Путь к XML (${XmlKind.allowedList})',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Обзор',
                          icon: const Icon(Icons.folder_open),
                          onPressed: _busy ? null : _pickFile,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final k in XmlKind.values)
                          ChoiceChip(
                            label: Text(k.fileName),
                            selected: XmlKind.fromPath(_path.text) == k,
                            onSelected: _busy ? null : (_) => _setDirectFile(k),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _busy ? null : _requestPermission,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Разрешить доступ к Storage'),
                    ),
                  ] else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _shz == ShizukuState.ready
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: _shz == ShizukuState.ready
                            ? Colors.greenAccent
                            : Colors.amber,
                      ),
                      title: Text(_shizukuLabel),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshShizuku,
                      ),
                    ),
                    if (_shz == ShizukuState.noPermission)
                      FilledButton.tonal(
                        onPressed: _ensureShizuku,
                        child: const Text('Выдать разрешение'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pkg,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Пакет игры',
                        hintText: 'com.ggf.sf2',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _found = {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _xmlFile,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Файл',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final k in XmlKind.values)
                                DropdownMenuItem(
                                  value: k.fileName,
                                  child: Text(
                                    _found.isEmpty
                                        ? k.fileName
                                        : '${k.fileName}  '
                                            '${_found.contains(k.fileName) ? '✓' : '✗'}',
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _xmlFile = v ?? _xmlFile),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Найти XML в gamedata',
                          icon: const Icon(Icons.search),
                          onPressed: _busy ? null : _scanFiles,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      isValidPackage(_pkgText)
                          ? _resolvedPath
                          : 'Введи корректное имя пакета',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _busy ? null : _open,
                    icon: const Icon(Icons.check),
                    label: Text(_busy ? 'Загрузка...' : 'Открыть файл'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================


class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final st = ctrl.statistics();
        final zs = ctrl.zones();

        return PopScope(
          canPop: !ctrl.dirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;

            final ok = await confirm(
              context,
              'Есть несохранённые изменения. Выйти без сохранения?',
            );

            if (ok && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                ctrl.dirty
                    ? 'RAID FORGE  ● изменён'
                    : 'RAID FORGE',
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
                        applicationName: 'SF2 Raid Forge',
                        children: const [
                          Text(
                            'XML-редактор raid_stages.\n\n'
                            'Zones / Battles, Warrior, Perks, Rules, '
                            'EquipItem, ComplexRules, RulesWithConditions, '
                            'Rewards, поиск, undo, диагностика, '
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

            // ------------------------------------------------
            // MAIN CONTENT
            // ------------------------------------------------

            body: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final e in {
                        'Zones': st.zones,
                        'Battles': st.battles,
                        'Warriors': st.warriors,
                        'Warrior Perks': st.warriorPerks,
                        'ComplexRules': st.complexRules,
                        'EquipItems': st.equipItems,
                        'Rule-Perks': st.rulePerks,
                        'Currencies': st.currencies,
                        'Conditions': st.conditions,
                      }.entries)
                        Chip(
                          label: Text('${e.key}: ${e.value}'),
                        ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                if (zs.isEmpty)
                  emptyNote('Зон нет.'),

                for (final zone in zs)
                  ListTile(
                    leading: const Icon(Icons.dns),
                    title: Text(zone.attr('Name', '?')),
                    subtitle: Text(
                      '${zone.attr('FileName', 'N/A')} • '
                      '${zone.kids('Battle').length} battles',
                    ),
                    onTap: () => go(
                      context,
                      ZoneScreen(zone),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          final r = await form(
                            context,
                            'Зона',
                            {
                              'Name': zone.attr('Name'),
                              'FileName': zone.attr('FileName'),
                            },
                          );

                          if (r != null) {
                            ctrl.editZone(
                              zone,
                              r['Name']!,
                              r['FileName']!,
                            );
                          }
                        } else if (v == 'del') {
                          if (await confirm(
                            context,
                            'Удалить зону ${zone.attr('Name')}?',
                          )) {
                            ctrl.deleteZone(zone);
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Переименовать / изменить'),
                        ),
                        PopupMenuItem(
                          value: 'del',
                          child: Text('Удалить'),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 80),
              ],
            ),

            // ------------------------------------------------
            // BOTTOM NAVIGATION
            // ------------------------------------------------

            bottomNavigationBar: BottomAppBar(
              height: 64,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Поиск босса',
                    icon: const Icon(Icons.search),
                    onPressed: () {
                      go(context, const SearchScreen());
                    },
                  ),

                  IconButton(
                    tooltip: 'Отменить (${ctrl.undoCount}/$maxUndo)',
                    icon: Badge(
                      isLabelVisible: ctrl.undoCount > 0,
                      label: Text('${ctrl.undoCount}'),
                      child: const Icon(Icons.undo),
                    ),
                    onPressed: () {
                      if (!ctrl.undo()) {
                        toast(
                          context,
                          'История изменений пуста.',
                        );
                      }
                    },
                  ),

                  IconButton(
                    tooltip: 'Сохранить + backup',
                    icon: const Icon(Icons.save),
                    onPressed: () => doSave(context),
                  ),

                  const Spacer(),

                  Text(
                    ctrl.dirty ? 'Есть изменения' : 'Сохранено',
                    style: TextStyle(
                      fontSize: 11,
                      color: ctrl.dirty
                          ? Colors.amber
                          : Colors.grey,
                    ),
                  ),

                  const SizedBox(width: 12),
                ],
              ),
            ),

            // ------------------------------------------------
            // CREATE ZONE
            // ------------------------------------------------

            floatingActionButton: FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Зона'),
              onPressed: () async {
                final r = await form(
                  context,
                  'Создание зоны',
                  {
                    'Name': '',
                    'FileName': '',
                  },
                );

                if (r == null) return;

                if (r['Name']!.isEmpty ||
                    r['FileName']!.isEmpty) {
                  if (context.mounted) {
                    toast(
                      context,
                      'Значение не может быть пустым.',
                    );
                  }
                  return;
                }

                ctrl.createZone(
                  r['Name']!,
                  r['FileName']!,
                );
              },
            ),
          ),
        );
      },
    );
  }
}


// ============================================================
// SEARCH
// ============================================================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final res = ctrl.searchBosses(q.trim());

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Name / Alias / Title / Template / Location',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
      body: q.trim().isEmpty
          ? emptyNote('Введите запрос')
          : res.isEmpty
              ? emptyNote('Ничего не найдено.')
              : ListView(
                  children: [
                    for (final (zone, battle) in res)
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(battle.attr('Name', '?')),
                        subtitle: Text(
                          '[${zone.attr('Name', '?')}] '
                          '${battle.attr('Title')}',
                        ),
                        onTap: () => go(
                          context,
                          BossScreen(battle),
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ============================================================
// DIAGNOSTICS
// ============================================================

class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final d = ctrl.diagnostics();

    final s = d.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('XML DIAGNOSTICS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (d.errors.isEmpty)
            const Text(
              '✓ Критических структурных ошибок не обнаружено.',
              style: TextStyle(color: Colors.greenAccent),
            )
          else ...[
            Text(
              'Ошибки: ${d.errors.length}',
              style: const TextStyle(color: Colors.redAccent),
            ),
            for (final e in d.errors)
              Text('✗ $e'),
          ],
          if (d.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Предупреждения: ${d.warnings.length}',
              style: const TextStyle(color: Colors.amber),
            ),
            for (final w in d.warnings)
              Text('• $w'),
          ],
          const SizedBox(height: 16),
          const Text(
            'Statistics',
            style: TextStyle(color: Colors.cyanAccent),
          ),
          if (ctrl.kind.isQuests)
            Text(
              'Quests=${s.quests}, Dojo=${s.dojos}, Include=${s.includes}',
            )
          else ...[
            Text(
              'Zones=${s.zones}, Battles=${s.battles}, Warriors=${s.warriors}',
            ),
            Text(
              'WarriorPerks=${s.warriorPerks}, '
              'RulePerks=${s.rulePerks}, '
              'ComplexRules=${s.complexRules}',
            ),
            Text(
              'EquipItems=${s.equipItems}, '
              'Currency=${s.currencies}, '
              'Conditions=${s.conditions}',
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// XML VIEW
// ============================================================

class XmlViewScreen extends StatelessWidget {
  final XmlElement el;

  const XmlViewScreen(this.el, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XML VIEW'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            ctrl.elementToXml(el),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ZONE
// ============================================================

class ZoneScreen extends StatelessWidget {
  final XmlElement zone;

  const ZoneScreen(this.zone, {super.key});

  Future<void> _cloneToZone(BuildContext context) async {
    final all = ctrl.battles();

    if (all.isEmpty) {
      toast(context, 'Нет боёв для клонирования.');
      return;
    }

    final i = await pick(
      context,
      'Шаблон босса',
      [
        for (final (z, b) in all)
          '[${z.attr('Name', '?')}] ${b.attr('Name', '?')}',
      ],
    );

    if (i == null || !context.mounted) return;

    final cur = all[i].$2.attr('Name', 'BOSS');

    final r = await form(
      context,
      'Новое Name',
      {'Name': '${cur}_COPY'},
    );

    if (r == null) return;

    ctrl.cloneBattleToZone(
      all[i].$2,
      zone,
      r['Name'],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final battles = zone.kids('Battle').toList();

        return Scaffold(
          appBar: AppBar(
            title: Text('ЗОНА — ${zone.attr('Name', '?')}'),
          ),
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(Icons.content_copy),
            label: const Text('Клонировать босса'),
            onPressed: () => _cloneToZone(context),
          ),
          body: battles.isEmpty
              ? emptyNote('Боёв нет.')
              : ListView(
                  children: [
                    for (final b in battles)
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(b.attr('Name', 'UNKNOWN')),
                        subtitle: Text(
                          '${b.attr('Title', 'N/A')} • '
                          'PWR=${ctrl.getWarrior(b)?.attr('WarriorPower', '?') ?? '?'}',
                        ),
                        onTap: () => go(
                          context,
                          BossScreen(b),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'dup') {
                              final r = await form(
                                context,
                                'Дублировать бой',
                                {
                                  'Name':
                                      '${b.attr('Name', 'BOSS')}_COPY',
                                },
                              );

                              if (r != null) {
                                ctrl.duplicateBattle(
                                  zone,
                                  b,
                                  r['Name'],
                                );
                              }
                            } else if (v == 'del') {
                              if (await confirm(
                                context,
                                'Удалить ${b.attr('Name')}?',
                              )) {
                                ctrl.deleteBattle(b);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'dup',
                              child: Text('Дублировать в этой зоне'),
                            ),
                            PopupMenuItem(
                              value: 'del',
                              child: Text('Удалить'),
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

// ============================================================
// BOSS
// ============================================================

class BossScreen extends StatelessWidget {
  final XmlElement battle;

  const BossScreen(this.battle, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final warrior = ctrl.getWarrior(battle);

        final fight = ctrl.getFight(battle);

        final name = battle.attr('Name', 'N/A');

        return Scaffold(
          appBar: AppBar(
            title: Text('БОСС — $name'),
          ),
          body: ListView(
            children: [
              tile(
                Icons.edit,
                'Имя / Title',
                sub: '$name / ${battle.attr('Title', 'N/A')}',
                onTap: () async {
                  final r = await form(
                    context,
                    'Имя / Title',
                    {
                      'Name': battle.attr('Name'),
                      'Title': battle.attr('Title'),
                    },
                  );

                  if (r != null) {
                    ctrl.editBossIdentity(
                      battle,
                      r['Name']!,
                      r['Title']!,
                    );
                  }
                },
              ),
              tile(
                Icons.place,
                'Location',
                sub: battle.attr('Location', 'N/A'),
                onTap: () async {
                  final r = await form(
                    context,
                    'Location',
                    {
                      'Location': battle.attr('Location'),
                    },
                  );

                  if (r != null) {
                    ctrl.changeAttr(
                      battle,
                      'Location',
                      r['Location']!,
                    );
                  }
                },
              ),
              tile(
                Icons.tune,
                'Battle attributes',
                sub: '${battle.attributes.length} attrs',
                onTap: () => go(
                  context,
                  AttrsScreen(battle, 'Battle attributes'),
                ),
              ),
              tile(
                Icons.person_outline,
                'Warrior Template',
                sub: warrior?.attr('Template', 'N/A') ?? 'N/A',
                onTap: () async {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  final r = await form(
                    context,
                    'Template',
                    {
                      'Template': warrior.attr('Template'),
                    },
                  );

                  if (r != null) {
                    ctrl.changeAttr(
                      warrior,
                      'Template',
                      r['Template']!,
                    );
                  }
                },
              ),
              tile(
                Icons.shield,
                'Warrior Power / Shields',
                sub:
                    '${warrior?.attr('WarriorPower', 'N/A') ?? 'N/A'} / '
                    '${warrior?.attr('ShieldTotal', '0') ?? '0'}',
                onTap: () async {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  final r = await form(
                    context,
                    'Power / Shields',
                    {
                      'WarriorPower':
                          warrior.attr('WarriorPower', '0'),
                      'ShieldTotal':
                          warrior.attr('ShieldTotal', '0'),
                    },
                  );

                  if (r != null) {
                    ctrl.editPowerShields(
                      warrior,
                      r['WarriorPower']!,
                      r['ShieldTotal']!,
                    );
                  }
                },
              ),
              tile(
                Icons.timer,
                'Rounds / RoundTime',
                sub:
                    '${fight?.attr('Rounds', 'N/A') ?? 'N/A'} / '
                    '${fight?.attr('RoundTime', 'N/A') ?? 'N/A'}s',
                onTap: () async {
                  if (fight == null) {
                    toast(context, 'Нет Fight');
                    return;
                  }

                  final r = await form(
                    context,
                    'Rounds / RoundTime',
                    {
                      'Rounds': fight.attr('Rounds', '0'),
                      'RoundTime': fight.attr('RoundTime', '999'),
                    },
                  );

                  if (r != null) {
                    ctrl.editRounds(
                      fight,
                      r['Rounds']!,
                      r['RoundTime']!,
                    );
                  }
                },
              ),
              tile(
                Icons.auto_awesome,
                'Warrior Perks',
                onTap: () {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  final perks = ctrl.ensurePerks(warrior);

                  go(
                    context,
                    PerksScreen(
                      perks,
                      rule: false,
                      title: 'WARRIOR PERKS',
                    ),
                  );
                },
              ),
              tile(
                Icons.rule,
                'Rules / Player Setup',
                onTap: () {
                  final rules = ctrl.ensureRules(battle);

                  if (rules == null) {
                    toast(context, 'Fight отсутствует.');
                    return;
                  }

                  go(context, RulesScreen(rules));
                },
              ),
              tile(
                Icons.card_giftcard,
                'Rewards / Currency',
                onTap: () => go(
                  context,
                  RewardsScreen(battle),
                ),
              ),
              tile(
                Icons.tune,
                'Warrior attributes',
                onTap: () {
                  if (warrior == null) {
                    toast(context, 'Нет Warrior');
                    return;
                  }

                  go(
                    context,
                    AttrsScreen(warrior, 'Warrior attributes'),
                  );
                },
              ),
              tile(
                Icons.code,
                'Полный XML Battle',
                onTap: () => go(
                  context,
                  XmlViewScreen(battle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// GENERIC ATTRIBUTES EDITOR
// ============================================================

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

// ============================================================
// PERKS
// ============================================================

class PerksScreen extends StatelessWidget {
  final XmlElement parent;

  final bool rule;

  final String title;

  const PerksScreen(
    this.parent, {
    required this.rule,
    required this.title,
    super.key,
  });

  Future<void> _preset(BuildContext context) async {
    final keys = presetPerks.keys.toList();

    final i = await pick(
      context,
      'PRESET PERKS',
      [
        for (final k in keys)
          '${presetPerks[k]!.$1}\n${presetPerks[k]!.$2}',
      ],
    );

    if (i != null) {
      ctrl.addPresetPerk(parent, keys[i]);
    }
  }

  Future<void> _custom(BuildContext context) async {
    final r = await form(
      context,
      rule ? 'Новый Rule-Perk' : 'Новый Perk',
      rule
          ? {'Name': '', 'ApplyTo': 'Player'}
          : {'Name': ''},
    );

    if (r == null || r['Name']!.isEmpty) return;

    if (!context.mounted) return;

    final addSet = await confirm(
      context,
      'Добавить <Set>?',
    );

    final apply = rule && r['ApplyTo']!.isNotEmpty
        ? r['ApplyTo']
        : null;

    ctrl.addCustomPerk(
      parent,
      r['Name']!,
      setAttrs: addSet ? {} : null,
      applyTo: apply,
    );
  }

  Future<void> _edit(
    BuildContext context,
    XmlElement p,
  ) async {
    final i = await pick(
      context,
      p.attr('Name', '?'),
      [
        rule ? 'Name / ApplyTo' : 'Name',
        'Set атрибуты',
        'Удалить',
      ],
    );

    if (i == null || !context.mounted) return;

    if (i == 0) {
      final r = await form(
        context,
        'Perk',
        rule
            ? {
                'Name': p.attr('Name'),
                'ApplyTo': p.attr('ApplyTo'),
              }
            : {
                'Name': p.attr('Name'),
              },
        hint: rule
            ? 'Пустой ApplyTo — удалить атрибут'
            : '',
      );

      if (r != null) {
        ctrl.editPerk(
          p,
          name: r['Name'],
          applyTo: rule ? r['ApplyTo'] : null,
        );
      }
    } else if (i == 1) {
      final set = ctrl.ensureSetNode(p);

      go(
        context,
        AttrsScreen(
          set,
          '${p.attr('Name', '?')} <Set>',
        ),
      );
    } else {
      if (await confirm(context, 'Удалить Perk?')) {
        ctrl.removeChild(p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!rule)
            IconButton(
              tooltip: 'Из пресета',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _preset(context),
            ),
          IconButton(
            tooltip: 'Кастомный',
            icon: const Icon(Icons.add),
            onPressed: () => _custom(context),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final items = parent.kids('Perk').toList();

          if (items.isEmpty) {
            return emptyNote('Perks отсутствуют.');
          }

          return ListView(
            children: [
              for (final p in items)
                ListTile(
                  title: Text(p.attr('Name', '?')),
                  subtitle: Text([
                    if (p.getAttribute('ApplyTo') != null)
                      'ApplyTo=${p.attr('ApplyTo')}',
                    if (p.kid('Set') != null)
                      p.kid('Set')!.attrMap.toString(),
                  ].join('   ')),
                  onTap: () => _edit(context, p),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// RULES
// ============================================================

class RulesScreen extends StatelessWidget {
  final XmlElement rules;

  const RulesScreen(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final avatar = rules.kid('Avatar');

        final cname = rules.kid('Name');

        return Scaffold(
          appBar: AppBar(
            title: const Text('RULES / PLAYER SETUP'),
          ),
          body: ListView(
            children: [
              tile(
                Icons.face,
                'Avatar / Name',
                sub:
                    'Avatar: ${avatar?.attr('Name') ?? '—'}   '
                    'Name: ${cname?.attr('Name') ?? '—'}',
                onTap: () async {
                  final r = await form(
                    context,
                    'Avatar / Character Name',
                    {
                      'Avatar Name': avatar?.attr('Name') ?? '',
                      'Character Name': cname?.attr('Name') ?? '',
                    },
                    hint: 'Пустое поле — удалить элемент',
                  );

                  if (r != null) {
                    ctrl.editAvatarName(
                      rules,
                      r['Avatar Name']!,
                      r['Character Name']!,
                    );
                  }
                },
              ),
              tile(
                Icons.checkroom,
                'Экипировка Player — EquipItem',
                sub: '${rules.kids('EquipItem').length}',
                onTap: () => go(
                  context,
                  EquipScreen(rules),
                ),
              ),
              tile(
                Icons.auto_awesome,
                'Rule-Perks',
                sub: '${rules.kids('Perk').length}',
                onTap: () => go(
                  context,
                  PerksScreen(
                    rules,
                    rule: true,
                    title: 'RULE-PERKS',
                  ),
                ),
              ),
              tile(
                Icons.rule,
                'ComplexRules',
                sub: '${rules.kids('ComplexRule').length}',
                onTap: () => go(
                  context,
                  ComplexRulesScreen(rules),
                ),
              ),
              tile(
                Icons.account_tree,
                'RulesWithConditions',
                sub: '${rules.kids('RulesWithConditions').length}',
                onTap: () => go(
                  context,
                  ConditionsScreen(rules),
                ),
              ),
              tile(
                Icons.delete_sweep,
                'Очистить ВСЕ пользовательские Rules',
                onTap: () async {
                  if (await confirm(
                    context,
                    'Будут удалены: Avatar, Name, EquipItem, Perk, '
                    'ComplexRule, RulesWithConditions. Продолжить?',
                  )) {
                    ctrl.clearUserRules(rules);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// EQUIPMENT
// ============================================================

class EquipScreen extends StatelessWidget {
  final XmlElement rules;

  const EquipScreen(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PLAYER EQUIPMENT'),
        actions: [
          IconButton(
            tooltip: 'Быстрый комплект',
            icon: const Icon(Icons.bolt),
            onPressed: () async {
              final r = await form(
                context,
                'Быстрый комплект Player',
                {
                  'Items': '',
                  'ApplyTo': 'Player',
                },
                hint: 'Предметы через пробел, например:\n'
                    'WEAPON_INDIA_24 BODY_WOMAN HELM_CROWN_OF_NIGHT '
                    'RANGED_IND21_KUNAI MAGIC_INDIA_24',
              );

              if (r != null) {
                ctrl.quickEquipment(
                  rules,
                  r['Items']!,
                  r['ApplyTo']!.isEmpty
                      ? 'Player'
                      : r['ApplyTo']!,
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Добавить',
            icon: const Icon(Icons.add),
            onPressed: () async {
              final r = await form(
                context,
                'Добавить EquipItem',
                {
                  'Item Name': '',
                  'ApplyTo': 'Player',
                },
              );

              if (r == null || r['Item Name']!.isEmpty) {
                return;
              }

              ctrl.addEquipItem(
                rules,
                r['Item Name']!,
                r['ApplyTo']!.isEmpty
                    ? 'Player'
                    : r['ApplyTo']!,
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final items = rules.kids('EquipItem').toList();

          if (items.isEmpty) {
            return emptyNote('EquipItem отсутствуют.');
          }

          return ListView(
            children: [
              for (final it in items)
                ListTile(
                  title: Text(it.attr('Name', '?')),
                  subtitle: Text(
                    'ApplyTo=${it.attr('ApplyTo', '—')}',
                  ),
                  onTap: () async {
                    final r = await form(
                      context,
                      'EquipItem',
                      {
                        'Name': it.attr('Name'),
                        'ApplyTo': it.attr('ApplyTo', 'Player'),
                      },
                    );

                    if (r != null && r['Name']!.isNotEmpty) {
                      ctrl.editEquipItem(
                        it,
                        r['Name']!,
                        r['ApplyTo']!,
                      );
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ctrl.removeChild(it),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// COMPLEX RULES
// ============================================================

class ComplexRulesScreen extends StatelessWidget {
  final XmlElement rules;

  const ComplexRulesScreen(this.rules, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('COMPLEX RULES'),
        actions: [
          IconButton(
            tooltip: 'Добавить из пресета',
            icon: const Icon(Icons.playlist_add),
            onPressed: () async {
              final keys = presetRules.keys.toList();

              final i = await pick(
                context,
                'COMPLEX RULE PRESETS',
                [
                  for (final k in keys)
                    '${presetRules[k]!.$1} → ${presetRules[k]!.$3}',
                ],
              );

              if (i != null) {
                ctrl.addComplexRulePreset(
                  rules,
                  keys[i],
                );
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final list = rules.kids('ComplexRule').toList();

          if (list.isEmpty) {
            return emptyNote('ComplexRule нет.');
          }

          return ListView(
            children: [
              for (final r in list)
                ListTile(
                  title: Text(
                    r.kid('Description')?.attr('Alias', '?') ?? '?',
                  ),
                  subtitle: Text(
                    ctrl.complexRuleChildren(r)
                        .map((e) => e.name.local)
                        .join(', '),
                  ),
                  onTap: () => go(
                    context,
                    ComplexRuleScreen(r),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить ComplexRule?',
                      )) {
                        ctrl.removeChild(r);
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

class ComplexRuleScreen extends StatelessWidget {
  final XmlElement rule;

  const ComplexRuleScreen(this.rule, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('COMPLEX RULE'),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить дочерний XML-узел',
        child: const Icon(Icons.add),
        onPressed: () async {
          final r = await form(
            context,
            'Добавить дочерний узел',
            {'Имя XML-узла': ''},
          );

          if (r == null || r['Имя XML-узла']!.isEmpty) {
            return;
          }

          final child = ctrl.addChild(
            rule,
            r['Имя XML-узла']!,
          );

          if (context.mounted) {
            go(
              context,
              AttrsScreen(child, child.name.local),
            );
          }
        },
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final children = ctrl.complexRuleChildren(rule);

          return ListView(
            children: [
              tile(
                Icons.label,
                'Alias',
                sub: rule.kid('Description')?.attr('Alias', '') ?? '',
                onTap: () async {
                  final r = await form(
                    context,
                    'Alias',
                    {
                      'Alias': rule.kid('Description')
                              ?.attr('Alias', '') ??
                          '',
                    },
                  );

                  if (r != null) {
                    ctrl.setComplexRuleAlias(
                      rule,
                      r['Alias']!,
                    );
                  }
                },
              ),
              const Divider(),
              if (children.isEmpty)
                emptyNote('Дочерних узлов нет.'),
              for (final ch in children)
                ListTile(
                  title: Text(ch.name.local),
                  subtitle: Text(ch.attrMap.toString()),
                  onTap: () => go(
                    context,
                    AttrsScreen(ch, ch.name.local),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить ${ch.name.local}?',
                      )) {
                        ctrl.removeChild(ch);
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

// ============================================================
// RULES WITH CONDITIONS
// ============================================================

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

// ============================================================
// REWARDS
// ============================================================

class RewardsScreen extends StatelessWidget {
  final XmlElement battle;

  const RewardsScreen(this.battle, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('REWARDS / CURRENCY'),
        actions: [
          IconButton(
            tooltip: 'Создать Reward',
            icon: const Icon(Icons.add),
            onPressed: () {
              final r = ctrl.createReward(battle);

              go(
                context,
                RewardScreen(r),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final rewards = battle.kids('Reward').toList();

          if (rewards.isEmpty) {
            return emptyNote('Rewards нет.');
          }

          return ListView(
            children: [
              for (var i = 0; i < rewards.length; i++)
                ListTile(
                  title: Text('Reward ${i + 1}'),
                  subtitle: Text(
                    'PrizeBase=${rewards[i].attr('PrizeBase', '—')} '
                    'Exp=${rewards[i].attr('Exp', '—')} '
                    'Bonus=${rewards[i].attr('Bonus', '—')}\n'
                    '${rewards[i].kids('Currency').map(
                          (c) => '↳ ${c.attr('Name', '?')} = '
                              '${c.attr('ExpectedValue', '?')}',
                        ).join('\n')}',
                  ),
                  isThreeLine: true,
                  onTap: () => go(
                    context,
                    RewardScreen(rewards[i]),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Удалить Reward?',
                      )) {
                        ctrl.removeChild(rewards[i]);
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

class RewardScreen extends StatelessWidget {
  final XmlElement reward;

  const RewardScreen(this.reward, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('REWARD'),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Добавить Currency',
        child: const Icon(Icons.add),
        onPressed: () async {
          final r = await form(
            context,
            'Добавить Currency',
            {
              'Currency Name': '',
              'ExpectedValue': '0',
            },
          );

          if (r == null || r['Currency Name']!.isEmpty) {
            return;
          }

          ctrl.addCurrency(
            reward,
            r['Currency Name']!,
            r['ExpectedValue']!.isEmpty
                ? '0'
                : r['ExpectedValue']!,
          );
        },
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final cs = reward.kids('Currency').toList();

          return ListView(
            children: [
              tile(
                Icons.edit,
                'PrizeBase / Exp / Bonus',
                sub:
                    'PrizeBase=${reward.attr('PrizeBase', '—')}  '
                    'Exp=${reward.attr('Exp', '—')}  '
                    'Bonus=${reward.attr('Bonus', '—')}',
                onTap: () async {
                  final r = await form(
                    context,
                    'Reward',
                    {
                      'PrizeBase': reward.attr('PrizeBase'),
                      'Exp': reward.attr('Exp'),
                      'Bonus': reward.attr('Bonus'),
                    },
                  );

                  if (r != null) {
                    ctrl.editReward(
                      reward,
                      prizeBase: r['PrizeBase']!,
                      exp: r['Exp']!,
                      bonus: r['Bonus']!,
                    );
                  }
                },
              ),
              const Divider(),
              if (cs.isEmpty)
                emptyNote('Currency нет.'),
              for (final c in cs)
                ListTile(
                  title: Text(c.attr('Name', '?')),
                  subtitle: Text(
                    'ExpectedValue=${c.attr('ExpectedValue', '?')}',
                  ),
                  onTap: () async {
                    final r = await form(
                      context,
                      'Currency',
                      {
                        'Name': c.attr('Name'),
                        'ExpectedValue': c.attr('ExpectedValue', '0'),
                      },
                    );

                    if (r != null) {
                      ctrl.editCurrency(
                        c,
                        r['Name']!,
                        r['ExpectedValue']!,
                      );
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ctrl.removeChild(c),
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

// ============================================================
// QUESTS EDITOR (quests.xml)
// ============================================================

void guard(BuildContext c, void Function() action) {
  try {
    action();
  } on RaidForgeException catch (e) {
    toast(c, e.message);
  }
}

final RegExp _tagRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_.\-]*$');

Widget editorBottomBar(BuildContext context) {
  return BottomAppBar(
    height: 64,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Отменить (${ctrl.undoCount}/$maxUndo)',
          icon: Badge(
            isLabelVisible: ctrl.undoCount > 0,
            label: Text('${ctrl.undoCount}'),
            child: const Icon(Icons.undo),
          ),
          onPressed: () {
            if (!ctrl.undo()) toast(context, 'История изменений пуста.');
          },
        ),
        IconButton(
          tooltip: 'Сохранить + backup',
          icon: const Icon(Icons.save),
          onPressed: () => doSave(context),
        ),
        const Spacer(),
        Text(
          ctrl.dirty ? 'Есть изменения' : 'Сохранено',
          style: TextStyle(
            fontSize: 11,
            color: ctrl.dirty ? Colors.amber : Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
  );
}

String _childTags(XmlElement? n) {
  if (n == null) return '—';

  final tags = n.childElements.map((e) => e.name.local).toList();

  if (tags.isEmpty) return '—';

  final shown = tags.take(8).join(', ');

  return tags.length > 8 ? '$shown … (+${tags.length - 8})' : shown;
}

// ------------------------------------------------------------
// HOME
// ------------------------------------------------------------

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

// ------------------------------------------------------------
// DOJO CHANGER
// ------------------------------------------------------------

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

// ------------------------------------------------------------
// ALL QUESTS
// ------------------------------------------------------------

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

// ------------------------------------------------------------
// RAW XML EDITOR
// ------------------------------------------------------------

class XmlEditScreen extends StatefulWidget {
  final XmlElement el;

  const XmlEditScreen(this.el, {super.key});

  @override
  State<XmlEditScreen> createState() => _XmlEditScreenState();
}

class _XmlEditScreenState extends State<XmlEditScreen> {
  late final TextEditingController _c =
      TextEditingController(text: ctrl.elementToXml(widget.el));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    try {
      ctrl.replaceElementXml(widget.el, _c.text);

      Navigator.of(context).pop(true);
    } on RaidForgeException catch (e) {
      toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('XML — ${widget.el.name.local}'),
        actions: [
          IconButton(
            tooltip: 'Применить',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _c,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
    );
  }
}
