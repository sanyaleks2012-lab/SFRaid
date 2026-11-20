import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'core/l10n.dart';
import 'core/perk_source.dart';
import 'core/storage.dart';

class AppState extends ChangeNotifier {
  String lang = 'en';
  PerkMergeMode perkMode = PerkMergeMode.extend;

  Future<void> load() async {
    final f = File(SfPaths.settings);
    if (!await f.exists()) return;
    try {
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      lang = m['lang'] as String? ?? lang;
      perkMode = m['perkMode'] == 'replace'
          ? PerkMergeMode.replace
          : PerkMergeMode.extend;
    } catch (_) {}
  }

  Future<void> _persist() => File(SfPaths.settings).writeAsString(
        jsonEncode({'lang': lang, 'perkMode': perkMode.name}),
      );

  Future<void> setLang(String code) async {
    lang = code;
    await L10n.load(code);
    await _persist();
    notifyListeners();
  }

  Future<void> setPerkMode(PerkMergeMode mode) async {
    perkMode = mode;
    await _persist();
    notifyListeners();
  }
}

final appState = AppState();