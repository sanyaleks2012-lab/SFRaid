import 'package:xml/xml.dart';
import 'l10n.dart';

enum XmlKind {
  raid('raid_stages_default.xml', 'Raid stages'),
  quests('quests.xml', 'Quests'),
  stages('stages.xml', 'Stages');

  final String fileName;
  final String title;
  const XmlKind(this.fileName, this.title);

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

class RaidForgeException implements Exception {
  final String key;
  final Map<String, Object?> args;
  RaidForgeException(this.key, [this.args = const {}]);

  String get message => tr(key, args);

  @override
  String toString() => message;
}

extension FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

XmlElement makeEl(String tag, [Map<String, String> attrs = const {}]) {
  return XmlElement(
    XmlName(tag),
    attrs.entries.map((e) => XmlAttribute(XmlName(e.key), e.value)),
  );
}

extension RaidXml on XmlElement {
  String attr(String name, [String def = '']) => getAttribute(name) ?? def;
  Iterable<XmlElement> kids(String tag) => findElements(tag);
  XmlElement? kid(String tag) => findElements(tag).firstOrNull;
  XmlElement? deep(String tag) => findAllElements(tag).firstOrNull;
  void put(String name, String value) => setAttribute(name, value);
}