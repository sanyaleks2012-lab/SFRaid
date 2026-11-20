import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'storage.dart';

class L10n {
  static Map<String, String> _fallback = {};
  static Map<String, String> _current = {};

  /// Читает язык с sdcard, при отсутствии — из ассетов. Недостающие ключи — из английского.
  static Future<void> load(String code) async {
    _fallback = await _read('en');
    _current = code == 'en' ? _fallback : await _read(code);
  }

  static Future<Map<String, String>> _read(String code) async {
    try {
      final f = File('${SfPaths.localisations}/$code.json');
      final raw = await f.exists()
          ? await f.readAsString()
          : await rootBundle.loadString('assets/localisations/$code.json');
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      try {
        final raw =
            await rootBundle.loadString('assets/localisations/$code.json');
        return (jsonDecode(raw) as Map)
            .map((k, v) => MapEntry('$k', '$v'));
      } catch (_) {
        return {};
      }
    }
  }

  static String t(String key, [Map<String, Object?> args = const {}]) {
    var s = _current[key] ?? _fallback[key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

String tr(String key, [Map<String, Object?> args = const {}]) =>
    L10n.t(key, args);