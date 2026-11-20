import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'perk_source.dart';
import 'shizuku_bridge.dart';
import 'storage.dart';
import 'xml_utils.dart';

part 'dojo.dart';

const int maxUndo = 30;

class DiagIssue {
  final bool error;
  final String key;
  final Map<String, Object?> args;
  const DiagIssue(this.error, this.key, [this.args = const {}]);
}

XmlElement parseFragment(String xml) {
  try {
    return XmlDocument.parse(xml).rootElement.copy();
  } on XmlException catch (e) {
    throw RaidForgeException('err.badXml', {'error': '$e'});
  }
}

class RaidForgeController extends ChangeNotifier {
  String filePath;
  final RaidIo io;
  final XmlKind kind;

  PerkLoad perkLoad = const PerkLoad([], 'none');
  List<PerkDef> get perkDefs => perkLoad.perks;

  late XmlDocument _doc;
  final List<XmlDocument> _undoStack = [];
  bool dirty = false;

  RaidForgeController(this.filePath, this.io, [this.kind = XmlKind.raid]);

  XmlElement get root => _doc.rootElement;
  int get undoCount => _undoStack.length;

  // ---------- LOAD / SAVE ----------

  Future<void> load() async {
    if (!await io.exists(filePath)) {
      throw RaidForgeException('err.fileNotFound', {'path': filePath});
    }
    try {
      _doc = XmlDocument.parse(await io.read(filePath));
    } on XmlException catch (e) {
      throw RaidForgeException('err.badXml', {'error': '$e'});
    }
    _undoStack.clear();
    dirty = false;
    notifyListeners();
  }

  Future<void> reloadPerks(PerkMergeMode mode) async {
    perkLoad = await loadPerkDefs(
      gamedata: dirOf(filePath),
      mode: mode,
      io: io,
    );
    notifyListeners();
  }

  Future<String> save() async {
    if (!await io.exists(filePath)) {
      throw RaidForgeException('err.fileNotFound', {'path': filePath});
    }
    final n = DateTime.now();
    final ts = '${n.year}${_p(n.month)}${_p(n.day)}_'
        '${_p(n.hour)}${_p(n.minute)}${_p(n.second)}';
    final backup = '$filePath.$ts.bak';
    await io.copy(filePath, backup);

    final body = _doc.toXmlString(pretty: true, indent: '  ');
    final out = body.trimLeft().startsWith('<?xml')
        ? body
        : '<?xml version="1.0" encoding="utf-8"?>\n$body';
    await io.write(filePath, out);

    dirty = false;
    notifyListeners();
    return backup;
  }

  static String _p(int n) => n.toString().padLeft(2, '0');

  String elementToXml(XmlElement el) =>
      el.toXmlString(pretty: true, indent: '  ');

  // ---------- UNDO ----------

  void _snapshot() {
    _undoStack.add(_doc.copy());
    if (_undoStack.length > maxUndo) _undoStack.removeAt(0);
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

  // ---------- RAID TREE ----------

  List<XmlElement> zones() {
    final node = root.kid('Zones');
    return node != null
        ? node.kids('Zone').toList()
        : root.findAllElements('Zone').toList();
  }

  /// (zone, battle) для всех боёв в порядке отображения.
  List<(XmlElement, XmlElement)> battles() {
    return [
      for (final z in zones())
        for (final b in z.kids('Battle')) (z, b),
    ];
  }

  XmlElement? battleAt(int index) {
    final all = battles();
    return index >= 0 && index < all.length ? all[index].$2 : null;
  }

  XmlElement? findBattle(String name) {
    for (final r in battles()) {
      if (r.$2.attr('Name') == name) return r.$2;
    }
    return null;
  }

  XmlElement? warriorOf(XmlElement battle) => battle.deep('Warrior');
  XmlElement? fightOf(XmlElement battle) => battle.deep('Fight');
  XmlElement? rulesOf(XmlElement battle) => fightOf(battle)?.kid('Rules');
  XmlElement? rewardOf(XmlElement battle) => battle.kid('Reward');

  List<int> searchIndices(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final all = battles();
    final out = <int>[];
    for (var i = 0; i < all.length; i++) {
      final b = all[i].$2;
      final w = warriorOf(b);
      final values = [
        b.attr('Name'),
        b.attr('Alias'),
        b.attr('Title'),
        b.attr('Location'),
        if (w != null) w.attr('Template'),
        if (w != null) w.attr('Tactic'),
      ];
      if (values.any((v) => v.toLowerCase().contains(q))) out.add(i);
    }
    return out;
  }

  // ---------- BATTLES ----------

  void deleteBattle(XmlElement battle) => _mutate(() => battle.remove());

  void duplicateBattle(XmlElement zone, XmlElement battle, String newName) {
    _mutate(() {
      final copy = battle.copy()..put('Name', newName);
      zone.children.insert(zone.children.indexOf(battle) + 1, copy);
    });
  }

  void renameBattle(XmlElement battle, String name, String title) {
    if (name.trim().isEmpty) throw RaidForgeException('err.nameEmpty');
    _mutate(() {
      battle.put('Name', name.trim());
      battle.put('Title', title);
    });
  }

  void setAttr(XmlElement el, String key, String value) {
    if (el.getAttribute(key) == value) return;
    _mutate(() => el.put(key, value));
  }

  void removeAttr(XmlElement el, String key) {
    if (el.getAttribute(key) == null) return;
    _mutate(() => el.removeAttribute(key));
  }

  void setWarriorStats(XmlElement warrior,
      {required String power, required String shields}) {
    _mutate(() {
      warrior.put('WarriorPower', power);
      warrior.put('ShieldTotal', shields);
    });
  }

  void setRounds(XmlElement fight,
      {required String rounds, required String roundTime}) {
    _mutate(() {
      fight.put('Rounds', rounds);
      fight.put('RoundTime', roundTime);
    });
  }

  void setReward(XmlElement battle,
      {required String prize, required String exp, required String bonus}) {
    _mutate(() {
      var r = rewardOf(battle);
      if (r == null) {
        r = makeEl('Reward');
        battle.children.add(r);
      }
      r.put('PrizeBase', prize);
      r.put('Exp', exp);
      r.put('Bonus', bonus);
    });
  }

  // ---------- PERKS ----------

  bool hasPerk(XmlElement warrior, String name) =>
      warrior.kid('Perks')?.kids('Perk').any((p) => p.attr('Name') == name) ??
      false;

  void addPerk(XmlElement warrior, PerkDef def) {
    _mutate(() {
      var container = warrior.kid('Perks');
      if (container == null) {
        container = makeEl('Perks');
        warrior.children.add(container);
      }
      container.children.add(def.toBattleXml());
    });
  }

  void removeNode(XmlElement el) => _mutate(() => el.remove());

  // ---------- RULES ----------

  XmlElement ensureRules(XmlElement fight) {
    final existing = fight.kid('Rules');
    if (existing != null) return existing;
    final rules = makeEl('Rules');
    _mutate(() => fight.children.add(rules));
    return rules;
  }

  void addEquip(XmlElement rules, String name, String applyTo) {
    _mutate(() => rules.children.add(
          makeEl('EquipItem', {'Name': name, 'ApplyTo': applyTo}),
        ));
  }

  // ---------- ROOT CHILDREN (QUESTS / STAGES) ----------

  List<XmlElement> quests() => root.kids('Quest').toList();

  List<XmlElement> rootChildren() => root.childElements.toList();

  XmlElement addQuest(String name, String event) {
    final q = makeEl('Quest', {'Name': name});
    q.children.add(makeEl('Events')..children.add(makeEl(event)));
    q.children.add(makeEl('Actions'));
    _mutate(() => root.children.add(q));
    return q;
  }

  void duplicateRootElement(XmlElement el, String newName) {
    final parent = el.parent;
    if (parent == null) throw RaidForgeException('err.notOwned');
    _mutate(() {
      final clone = el.copy();
      if (newName.isNotEmpty) clone.put('Name', newName);
      parent.children.insert(parent.children.indexOf(el) + 1, clone);
    });
  }

  void replaceElementXml(XmlElement old, String xml) {
    final fresh = parseFragment(xml);
    final parent = old.parent;
    if (parent == null) throw RaidForgeException('err.notOwned');
    _mutate(() {
      parent.children.insert(parent.children.indexOf(old), fresh);
      old.remove();
    });
  }

  // ---------- DIAGNOSTICS ----------

  List<DiagIssue> diagnostics() {
    if (kind == XmlKind.quests) return _questDiagnostics();

    final out = <DiagIssue>[];
    if (zones().isEmpty) out.add(const DiagIssue(false, 'diag.noZones'));
    for (final (_, b) in battles()) {
      final n = b.attr('Name', '?');
      if (warriorOf(b) == null) {
        out.add(DiagIssue(false, 'diag.noWarrior', {'name': n}));
      }
      if (fightOf(b) == null) {
        out.add(DiagIssue(false, 'diag.noFight', {'name': n}));
      }
      for (final p in b.findAllElements('Perk')) {
        if (p.attr('Name').isEmpty) {
          out.add(DiagIssue(true, 'diag.perkNoName', {'name': n}));
        }
      }
    }
    return out;
  }

  List<DiagIssue> _questDiagnostics() {
    final out = <DiagIssue>[];
    final counts = <String, int>{};
    for (final q in quests()) {
      final n = q.attr('Name');
      if (n.isEmpty) {
        out.add(const DiagIssue(true, 'diag.questNoName'));
        continue;
      }
      counts[n] = (counts[n] ?? 0) + 1;
    }
    counts.forEach((n, c) {
      if (c > 1) out.add(DiagIssue(false, 'diag.dupQuest', {'name': n, 'count': c}));
    });
    out.addAll(dojoDiagnostics());
    return out;
  }
}