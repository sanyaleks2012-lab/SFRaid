// lib/shizuku_bridge.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

// ============================================================
// SHIZUKU CHANNEL
// ============================================================

enum ShizukuState { notInstalled, notRunning, noPermission, ready }

class ShizukuBridge {
  static const _ch = MethodChannel('raidforge/shizuku');

  static Future<ShizukuState> state() async {
    try {
      final r = await _ch.invokeMethod<String>('state');
      return ShizukuState.values.firstWhere(
        (e) => e.name == r,
        orElse: () => ShizukuState.notInstalled,
      );
    } on PlatformException {
      return ShizukuState.notInstalled;
    } on MissingPluginException {
      return ShizukuState.notInstalled;
    }
  }

  static Future<bool> requestPermission() async =>
      await _ch.invokeMethod<bool>('requestPermission') ?? false;

  static Future<bool> exists(String path) async =>
      await _ch.invokeMethod<bool>('exists', {'path': path}) ?? false;

  static Future<String> readText(String path) async {
    final bytes =
        await _ch.invokeMethod<Uint8List>('read', {'path': path});
    return utf8.decode(bytes ?? Uint8List(0));
  }

  static Future<void> writeText(String path, String text) async {
    await _ch.invokeMethod('write', {
      'path': path,
      'data': Uint8List.fromList(utf8.encode(text)),
    });
  }

  static Future<void> copy(String src, String dst) =>
      _ch.invokeMethod('copy', {'src': src, 'dst': dst});

  static Future<List<String>> list(String dir) async {
    final r = await _ch.invokeMethod<String>('list', {'dir': dir});
    return (r ?? '')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

// ============================================================
// PATHS
// ============================================================

final RegExp _pkgRe =
    RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$');

bool isValidPackage(String pkg) => _pkgRe.hasMatch(pkg);

String gamedataDir(String pkg) =>
    '/storage/emulated/0/Android/data/$pkg/files/mod/gamedata';

// ============================================================
// FILE IO ABSTRACTION
// ============================================================

abstract class RaidIo {
  Future<bool> exists(String path);
  Future<String> read(String path);
  Future<void> copy(String src, String dst);
  Future<void> write(String path, String content);
}

/// Обычный доступ (MANAGE_EXTERNAL_STORAGE).
class DirectIo implements RaidIo {
  @override
  Future<bool> exists(String p) => File(p).exists();

  @override
  Future<String> read(String p) => File(p).readAsString();

  @override
  Future<void> copy(String s, String d) async {
    await File(s).copy(d);
  }

  @override
  Future<void> write(String path, String content) async {
    final dst = File(path);
    final tmp = File(
      '${dst.parent.path}/.raidforge_${DateTime.now().microsecondsSinceEpoch}.xml',
    );
    try {
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(path);
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }
}

/// Доступ через Shizuku (shell-uid) — работает в Android/data.
/// Запись идёт `cat > file`, а не tmp+mv: так сохраняется владелец
/// файла и игра продолжает его читать.
class ShizukuIo implements RaidIo {
  @override
  Future<bool> exists(String p) => ShizukuBridge.exists(p);

  @override
  Future<String> read(String p) => ShizukuBridge.readText(p);

  @override
  Future<void> copy(String s, String d) => ShizukuBridge.copy(s, d);

  @override
  Future<void> write(String path, String content) =>
      ShizukuBridge.writeText(path, content);
}
