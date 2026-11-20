import 'package:xml/xml.dart';
import 'shizuku_bridge.dart';
import 'storage.dart';
import 'xml_utils.dart';

enum PerkMergeMode { replace, extend }

class PerkDef {
  final String name;
  final String origin; // 'enchant' | 'perks'
  final XmlElement? setNode;

  const PerkDef({
    required this.name,
    required this.origin,
    required this.setNode,
  });

  String get setSummary => setNode == null
      ? ''
      : setNode!.attributes
          .map((a) => '${a.name.local}=${a.value}')
          .join('  ');

  /// Элемент для Warrior Perks: только имя и блок Set, триггеры остаются в файле перков.
  XmlElement toBattleXml() {
    final el = makeEl('Perk', {'Name': name});
    if (setNode != null) el.children.add(setNode!.copy());
    return el;
  }
}

class PerkLoad {
  final List<PerkDef> perks;
  final String origin; // 'enchant' | 'perks' | 'merged' | 'none'
  const PerkLoad(this.perks, this.origin);
}

/// Enchantment.xml из SFRaid/consumables, при его отсутствии perks.xml из gamedata.
/// extend: perks.xml + Enchantment (при совпадении имени побеждает Enchantment).
/// replace: только Enchantment, если он есть.
Future<PerkLoad> loadPerkDefs({
  required String gamedata,
  required PerkMergeMode mode,
  required RaidIo io,
}) async {
  final enchant = await _parse(io, SfPaths.enchantment, 'enchant');
  final base = await _parse(io, '$gamedata/perks.xml', 'perks');

  if (enchant == null && base == null) return const PerkLoad([], 'none');
  if (enchant == null) return PerkLoad(base!, 'perks');
  if (base == null || mode == PerkMergeMode.replace) {
    return PerkLoad(enchant, 'enchant');
  }

  final byName = {for (final p in base) p.name: p};
  for (final p in enchant) {
    byName[p.name] = p;
  }
  return PerkLoad(byName.values.toList(), 'merged');
}

Future<List<PerkDef>?> _parse(RaidIo io, String path, String origin) async {
  if (!await io.exists(path)) return null;
  final doc = XmlDocument.parse(await io.read(path));
  return [
    for (final p in doc.findAllElements('Perk'))
      if (p.attr('Name').isNotEmpty)
        PerkDef(name: p.attr('Name'), origin: origin, setNode: p.kid('Set')),
  ];
}