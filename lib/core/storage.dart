import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class SfPaths {
  static const root = '/storage/emulated/0/SFRaid';
  static const lua = '$root/lua';
  static const save = '$root/save';
  static const consumables = '$root/consumables';
  static const localisations = '$root/localisations';
  static const settings = '$save/settings.json';
  static const recent = '$save/recent.json';
  static const enchantment = '$consumables/Enchantment.xml';
}

const supportedLocales = ['en', 'ru'];


String dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i > 0 ? path.substring(0, i) : '/';
}

Future<bool> requestAllFilesAccess() async {
  if (!Platform.isAndroid) return true;
  try {
    final s = await Permission.manageExternalStorage.status;
    if (s.isGranted) return true;
    return (await Permission.manageExternalStorage.request()).isGranted;
  } catch (_) {
    return false;
  }
}

/// Создаёт папки SFRaid, распаковывает локализации и пример плагина.
/// Создаёт папки SFRaid, синхронизирует локализации и пишет пример плагина.
Future<void> ensureLayout() async {
  for (final d in [
    SfPaths.lua,
    '${SfPaths.lua}/examples',
    SfPaths.save,
    SfPaths.consumables,
    SfPaths.localisations,
  ]) {
    await Directory(d).create(recursive: true);
  }
  for (final code in supportedLocales) {
    await _syncLocale(code);
  }
  final ex = File('${SfPaths.lua}/examples/hello.lua');
  if (!await ex.exists()) await ex.writeAsString(exampleLua);
}

/// Перезаписывает файл на sdcard, если версия в ассетах новее.
/// Ручные правки в этом файле при повышении _version будут потеряны.
Future<void> _syncLocale(String code) async {
  final asset = await rootBundle.loadString('assets/localisations/$code.json');
  final f = File('${SfPaths.localisations}/$code.json');
  var fileVersion = -1;
  if (await f.exists()) {
    try {
      final m = jsonDecode(await f.readAsString()) as Map;
      fileVersion = (m['_version'] as int?) ?? 0;
    } catch (_) {
      fileVersion = 0;
    }
  }
  final assetVersion =
      ((jsonDecode(asset) as Map)['_version'] as int?) ?? 0;
  if (fileVersion < assetVersion) {
    await f.writeAsString(asset);
  }
}

Future<List<String>> loadRecentPackages() async {
  final f = File(SfPaths.recent);
  if (!await f.exists()) return [];
  try {
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return List<String>.from(m['packages'] as List);
  } catch (_) {
    return [];
  }
}

Future<void> rememberPackage(String pkg) async {
  final rest = (await loadRecentPackages()).where((p) => p != pkg);
  final list = [pkg, ...rest].take(8).toList();
  await File(SfPaths.recent).writeAsString(jsonEncode({'packages': list}));
}

const exampleLua = r'''
-- Пример плагина SFRaid. Файлы из SFRaid/lua загружаются при открытии XML.
-- Хуки:  onLoad()  — после открытия файла
--        onSave()  — перед сохранением
-- Меню:  sf.menu("подпись", "имя_функции")
-- API:   sf.kind(), sf.battles(), sf.getBattleAttr(b, attr), sf.setBattleAttr(b, attr, v),
--        sf.getWarriorAttr(b, attr), sf.setWarriorAttr(b, attr, v),
--        sf.addPerk(battle, perkName), sf.getVar(key), sf.setVar(key, value), sf.log(msg)

function onLoad()
  sf.log("kind=" .. sf.kind() .. " battles=" .. #sf.battles())
end

function onSave()
  sf.log("saving")
end

sf.menu("Double all warrior power", "doublePower")

function doublePower()
  for _, name in ipairs(sf.battles()) do
    local p = tonumber(sf.getWarriorAttr(name, "WarriorPower")) or 0
    sf.setWarriorAttr(name, "WarriorPower", tostring(p * 2))
  end
  sf.log("power doubled")
end
''';
/// Принудительно перезаписывает файлы на sdcard из ассетов.
Future<void> resetLocalisations() async {
  await Directory(SfPaths.localisations).create(recursive: true);
  for (final code in supportedLocales) {
    await File('${SfPaths.localisations}/$code.json').writeAsString(
      await rootBundle.loadString('assets/localisations/$code.json'),
    );
  }
}