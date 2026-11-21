import '../core/raid_io.dart';

import 'shizuku_bridge.dart';

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
