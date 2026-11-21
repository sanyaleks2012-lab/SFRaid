import 'package:xml/xml.dart';

/// Одно додзё в «Dojo Changer» из quests.xml.
///
/// Логика файла:
///  • Page-квест  (Events/Activate, Dialog Title="DojoChangerTitle") —
///    страница листалки: кнопки NEXT / SELECT / BACK, текст Line.
///  • Load-квест  (Events/Activate, ChangeDojoLocation) — срабатывает по
///    SELECT: ставит DojoLoader, меняет локацию, ChangeScene в Dojo.
///  • Стартовый If в DojoChanger_LoadSelectedDojo (или отдельном квесте)
///    восстанавливает выбранное додзё при запуске игры.
class DojoEntry {
  final XmlElement page;
  final XmlElement? load;
  final XmlElement? startupIf;
  final String pageAction;
  final String loadAction;
  final String labelKey;
  final String location;
  final String loader;
  final bool linked;

  const DojoEntry({
    required this.page,
    required this.load,
    required this.startupIf,
    required this.pageAction,
    required this.loadAction,
    required this.labelKey,
    required this.location,
    required this.loader,
    required this.linked,
  });

  String get title => labelKey.isEmpty ? pageAction : labelKey;
}
