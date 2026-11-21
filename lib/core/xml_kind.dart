// Допустимые XML-файлы редактора (строгое соответствие имени).

enum XmlKind {
  raid('raid_stages_default.xml', 'Raid stages'),
  quests('quests.xml', 'Quests'),
  stages('stages.xml', 'Stages');

  final String fileName;
  final String title;

  const XmlKind(this.fileName, this.title);

  bool get isQuests => this == XmlKind.quests;

  /// Определяет тип по имени файла (строгое совпадение).
  static XmlKind? fromPath(String path) {
    final base = path.split(RegExp(r'[\\/]')).last.trim().toLowerCase();

    for (final k in XmlKind.values) {
      if (k.fileName == base) return k;
    }

    return null;
  }

  static String get allowedList =>
      XmlKind.values.map((k) => k.fileName).join(', ');
}
