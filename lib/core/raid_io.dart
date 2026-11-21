/// Абстракция доступа к XML-файлам: обычный (dart:io) или через Shizuku.
abstract class RaidIo {
  Future<bool> exists(String path);
  Future<String> read(String path);
  Future<void> copy(String src, String dst);
  Future<void> write(String path, String content);
}
