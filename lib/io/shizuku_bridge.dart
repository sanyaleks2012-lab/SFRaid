import 'dart:convert';

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
