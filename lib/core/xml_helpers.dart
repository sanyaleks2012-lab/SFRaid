import 'package:xml/xml.dart';

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class RaidForgeException implements Exception {
  final String message;

  RaidForgeException(this.message);

  @override
  String toString() => message;
}

XmlElement makeEl(
  String tag, [
  Map<String, String> attrs = const {},
]) {
  return XmlElement(
    XmlName(tag),
    attrs.entries.map(
      (e) => XmlAttribute(XmlName(e.key), e.value),
    ),
  );
}

extension RaidXml on XmlElement {
  String attr(String name, [String def = '']) =>
      getAttribute(name) ?? def;

  Iterable<XmlElement> kids(String tag) => findElements(tag);

  XmlElement? kid(String tag) => findElements(tag).firstOrNull;

  XmlElement? deep(String tag) => findAllElements(tag).firstOrNull;

  void put(String name, String value) => setAttribute(name, value);

  Map<String, String> get attrMap => {
        for (final a in attributes) a.name.local: a.value,
      };
}

typedef BattleRef = (XmlElement zone, XmlElement battle);

XmlElement parseFragment(String xml) {
  try {
    return XmlDocument.parse(xml).rootElement.copy();
  } on XmlException catch (e) {
    throw RaidForgeException('XML некорректен:\n$e');
  }
}
