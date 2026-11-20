import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:lua_dardo/lua.dart';
import '../core/raid_controller.dart';
import '../core/storage.dart';
import '../core/xml_utils.dart';

typedef _LuaFn = int Function(LuaState ls);

class LuaMenuItem {
  final String plugin;
  final String label;
  final String fn;
  const LuaMenuItem(this.plugin, this.label, this.fn);
}

class PluginHost extends ChangeNotifier {
  final List<String> logs = [];
  final List<String> plugins = [];
  final List<LuaMenuItem> menu = [];
  final Map<String, String> vars = {};

  RaidForgeController? _ctrl;
  LuaState? _ls;
  String _current = '';

  /// Загружает все .lua из SFRaid/lua (по имени), затем вызывает onLoad.
  Future<void> reload(RaidForgeController ctrl) async {
    _ctrl = ctrl;
    logs.clear();
    plugins.clear();
    menu.clear();

    final ls = LuaState.newState();
    ls.openLibs();
    _ls = ls;
    _registerApi(ls);

    final files = <File>[];
    final dir = Directory(SfPaths.lua);
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.lua')) files.add(e);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    for (final f in files) {
      _current = f.uri.pathSegments.last;
      plugins.add(_current);
      try {
        final ok = ls.doString(await f.readAsString());
        if (!ok) _error(ls);
      } catch (e) {
        logs.add('[$_current] $e');
      }
    }
    _current = '';
    fire('onLoad');
    notifyListeners();
  }

  /// Хуки: onLoad, onSave.
  void fire(String hook) {
  final ls = _ls;
  if (ls == null) return;
  ls.getGlobal(hook);
  if (ls.isNil(-1)) {
    ls.pop(1);
    return;
  }
  final status = ls.pCall(0, 0, 0);
  if (status != ThreadStatus.values.first) _error(ls);
}

    void runMenu(LuaMenuItem item) {
    _current = item.plugin;
    final ls = _ls;
    if (ls == null) return;
    ls.getGlobal(item.fn);
    if (ls.isNil(-1)) {
      ls.pop(1);
    } else {
      final status = ls.pCall(0, 0, 0);
      if (status != ThreadStatus.values.first) {
        _error(ls);
      } else {
        logs.add('[${item.plugin}] ${item.label}');
      }
    }
    _current = '';
    notifyListeners();
  }

  void _error(LuaState ls) {
    logs.add('[$_current] ${ls.toStr(-1) ?? 'lua error'}');
    ls.pop(1);
  }

  // ---------- API для скриптов: таблица sf ----------

  /// checkString может вернуть null, поэтому аргумент читается через этот хелпер.
  String _a(LuaState s, int i) => s.checkString(i) ?? '';

  void _registerApi(LuaState ls) {
    ls.newTable();

    _reg(ls, 'log', (s) {
      logs.add('[$_current] ${_a(s, 1)}');
      return 0;
    });

    _reg(ls, 'kind', (s) {
      s.pushString(_ctrl!.kind.name);
      return 1;
    });

    _reg(ls, 'battles', (s) {
      final names = _ctrl!.battles().map((r) => r.$2.attr('Name')).toList();
      s.createTable(names.length, 0);
      for (var i = 0; i < names.length; i++) {
        s.pushInteger(i + 1);
        s.pushString(names[i]);
        s.setTable(-3);
      }
      return 1;
    });

    _reg(ls, 'getBattleAttr', (s) {
      final b = _ctrl!.findBattle(_a(s, 1));
      _push(s, b?.getAttribute(_a(s, 2)));
      return 1;
    });

    _reg(ls, 'setBattleAttr', (s) {
      final b = _ctrl!.findBattle(_a(s, 1));
      if (b != null) _ctrl!.setAttr(b, _a(s, 2), _a(s, 3));
      return 0;
    });

    _reg(ls, 'getWarriorAttr', (s) {
      final b = _ctrl!.findBattle(_a(s, 1));
      final w = b == null ? null : _ctrl!.warriorOf(b);
      _push(s, w?.getAttribute(_a(s, 2)));
      return 1;
    });

    _reg(ls, 'setWarriorAttr', (s) {
      final b = _ctrl!.findBattle(_a(s, 1));
      final w = b == null ? null : _ctrl!.warriorOf(b);
      if (w != null) _ctrl!.setAttr(w, _a(s, 2), _a(s, 3));
      return 0;
    });

    _reg(ls, 'addPerk', (s) {
      final b = _ctrl!.findBattle(_a(s, 1));
      final w = b == null ? null : _ctrl!.warriorOf(b);
      final perkName = _a(s, 2);
      final def = _ctrl!.perkDefs.where((p) => p.name == perkName).firstOrNull;
      if (w != null && def != null) _ctrl!.addPerk(w, def);
      return 0;
    });

    _reg(ls, 'getVar', (s) {
      _push(s, vars['$_current.${_a(s, 1)}']);
      return 1;
    });

    _reg(ls, 'setVar', (s) {
      vars['$_current.${_a(s, 1)}'] = _a(s, 2);
      return 0;
    });

    _reg(ls, 'menu', (s) {
      menu.add(LuaMenuItem(_current, _a(s, 1), _a(s, 2)));
      return 0;
    });

    ls.setGlobal('sf');
  }

  void _reg(LuaState ls, String name, _LuaFn fn) {
    ls.pushDartFunction(fn);
    ls.setField(-2, name);
  }

  void _push(LuaState s, String? v) {
    if (v == null) {
      s.pushNil();
    } else {
      s.pushString(v);
    }
  }
}

final pluginHost = PluginHost();