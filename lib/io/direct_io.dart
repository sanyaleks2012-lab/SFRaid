import 'dart:io';

import '../core/raid_io.dart';

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
