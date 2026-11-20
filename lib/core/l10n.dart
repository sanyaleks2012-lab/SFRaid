import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'storage.dart';

class L10n {
  static Map<String, String> _base = {};
  static Map<String, String> _active = {};

  /// Порядок: встроенный en (полный набор) → встроенный выбранный язык →
  /// файл на sdcard (может быть неполным). Недостающее берётся из встроенного en.
  static Future<void> load(String code) async {
    _base = await _bundled('en');
    final bundled = code == 'en' ? _base : await _bundled(code);
    final external = await _external(code);
    _active = {...bundled, ...external};
  }

  static Future<Map<String, String>> _bundled(String code) async {
    try {
      return _decode(
        await rootBundle.loadString('assets/localisations/$code.json'),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, String>> _external(String code) async {
    try {
      final f = File('${SfPaths.localisations}/$code.json');
      if (!await f.exists()) return {};
      return _decode(await f.readAsString());
    } catch (_) {
      return {};
    }
  }

  static Map<String, String> _decode(String raw) =>
      (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));

  static String t(String key, [Map<String, Object?> args = const {}]) {
    var s = _active[key] ?? _base[key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

String tr(String key, [Map<String, Object?> args = const {}]) =>
    L10n.t(key, args);