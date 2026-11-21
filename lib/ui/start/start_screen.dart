import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config.dart';
import '../../core/raid_forge_controller.dart';
import '../../core/raid_io.dart';
import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../../core/xml_kind.dart';
import '../../io/direct_io.dart';
import '../../io/paths.dart';
import '../../io/shizuku_bridge.dart';
import '../../io/shizuku_io.dart';
import '../../io/storage_permission.dart';
import '../common/feedback.dart';
import '../common/navigation.dart';
import '../home/home_screen.dart';
import '../quests/quests_home_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

enum AccessMode { direct, shizuku }

class _StartScreenState extends State<StartScreen> {
  late final TextEditingController _path;
  final _pkg = TextEditingController(text: 'com.onerdna.sfml');

  AccessMode _mode = AccessMode.direct;
  ShizukuState _shz = ShizukuState.notInstalled;
  // Файлы, найденные в gamedata при последнем поиске (только 3 допустимых).
  Set<String> _found = {};
  String _xmlFile = XmlKind.raid.fileName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: defaultFilePath);
    _refreshShizuku();
  }

  @override
  void dispose() {
    _path.dispose();
    _pkg.dispose();
    super.dispose();
  }

  String get _pkgText => _pkg.text.trim();

  String get _resolvedPath => _mode == AccessMode.shizuku
      ? '${gamedataDir(_pkgText)}/$_xmlFile'
      : _path.text.trim();

  String get _shizukuLabel => switch (_shz) {
        ShizukuState.notInstalled => 'Shizuku не установлен',
        ShizukuState.notRunning => 'Shizuku не запущен',
        ShizukuState.noPermission => 'Нужно разрешение Shizuku',
        ShizukuState.ready => 'Shizuku готов',
      };

  Future<void> _refreshShizuku() async {
    final s = await ShizukuBridge.state();
    if (mounted) setState(() => _shz = s);
  }

  Future<bool> _ensureShizuku() async {
    await _refreshShizuku();
    if (_shz == ShizukuState.noPermission) {
      await ShizukuBridge.requestPermission();
      await _refreshShizuku();
    }
    if (_shz != ShizukuState.ready && mounted) {
      toast(context, '$_shizukuLabel. Запусти Shizuku и выдай доступ.');
    }
    return _shz == ShizukuState.ready;
  }

  Future<void> _scanFiles() async {
    if (!isValidPackage(_pkgText)) {
      toast(context, 'Некорректное имя пакета.');
      return;
    }
    if (!await _ensureShizuku()) return;
    try {
      final all = await ShizukuBridge.list(gamedataDir(_pkgText));
      final found = <String>{
        for (final k in XmlKind.values)
          if (all.contains(k.fileName)) k.fileName,
      };
      if (!mounted) return;
      setState(() {
        _found = found;
        if (found.isNotEmpty && !found.contains(_xmlFile)) {
          _xmlFile = found.contains(XmlKind.raid.fileName)
              ? XmlKind.raid.fileName
              : found.first;
        }
      });
      if (found.isEmpty) {
        toast(context, 'В gamedata нет файлов: ${XmlKind.allowedList}.');
      }
    } catch (e) {
      if (mounted) toast(context, 'Ошибка чтения папки: $e');
    }
  }

  Future<void> _requestPermission() async {
    final granted = await requestStoragePermission();
    if (!mounted) return;
    if (granted) {
      toast(context, 'Доступ ко всем файлам разрешён.');
    } else {
      toast(context, 'Разрешение не выдано. Проверь специальный доступ к файлам.');
      await openAppSettings();
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        allowMultiple: false,
      );
      if (!mounted || result == null) return;
      final selected = result.files.single.path;
      if (selected == null) {
        toast(context, 'Не удалось получить путь к файлу.');
        return;
      }
      if (XmlKind.fromPath(selected) == null) {
        toast(context, 'Можно открыть только: ${XmlKind.allowedList}.');
        return;
      }
      setState(() => _path.text = selected);
    } catch (e) {
      if (mounted) toast(context, 'Ошибка выбора файла: $e');
    }
  }

  /// Меняет имя файла в пути (папка остаётся прежней).
  void _setDirectFile(XmlKind k) {
    final p = _path.text.trim();
    final i = p.lastIndexOf('/');
    final dir = i > 0 ? p.substring(0, i) : '/storage/emulated/0';
    setState(() => _path.text = '$dir/${k.fileName}');
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final RaidIo io;
      if (_mode == AccessMode.shizuku) {
        if (!isValidPackage(_pkgText)) {
          toast(context, 'Некорректное имя пакета.');
          return;
        }
        if (!await _ensureShizuku()) return;
        io = ShizukuIo();
      } else {
        if (!await requestStoragePermission()) {
          if (!mounted) return;
          toast(context, 'Сначала разреши доступ ко всем файлам.');
          await openAppSettings();
          return;
        }
        io = DirectIo();
      }
      final path = _resolvedPath;
      if (path.isEmpty) {
        if (mounted) toast(context, 'Укажи путь к XML-файлу.');
        return;
      }
      final kind = XmlKind.fromPath(path);
      if (kind == null) {
        if (mounted) {
          toast(context, 'Можно открыть только: ${XmlKind.allowedList}.');
        }
        return;
      }
      final c = RaidForgeController(path, io, kind);
      await c.load();
      if (!mounted) {
        c.dispose();
        return;
      }
      ctrl = c;
      // quests.xml открывается в специальном редакторе квестов / додзё.
      go(
        context,
        kind.isQuests ? const QuestsHomeScreen() : const HomeScreen(),
      );
    } on RaidForgeException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shizuku = _mode == AccessMode.shizuku;
    return Scaffold(
      appBar: AppBar(title: const Text('SF2 • RAID FORGE')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<AccessMode>(
                    segments: const [
                      ButtonSegment(
                        value: AccessMode.direct,
                        icon: Icon(Icons.folder),
                        label: Text('Файлы'),
                      ),
                      ButtonSegment(
                        value: AccessMode.shizuku,
                        icon: Icon(Icons.adb),
                        label: Text('Shizuku'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() => _mode = s.first);
                      if (s.first == AccessMode.shizuku) _refreshShizuku();
                    },
                  ),
                  const SizedBox(height: 20),
                  if (!shizuku) ...[
                    TextField(
                      controller: _path,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Путь к XML (${XmlKind.allowedList})',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Обзор',
                          icon: const Icon(Icons.folder_open),
                          onPressed: _busy ? null : _pickFile,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final k in XmlKind.values)
                          ChoiceChip(
                            label: Text(k.fileName),
                            selected: XmlKind.fromPath(_path.text) == k,
                            onSelected: _busy ? null : (_) => _setDirectFile(k),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _busy ? null : _requestPermission,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Разрешить доступ к Storage'),
                    ),
                  ] else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _shz == ShizukuState.ready
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: _shz == ShizukuState.ready
                            ? Colors.greenAccent
                            : Colors.amber,
                      ),
                      title: Text(_shizukuLabel),
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshShizuku,
                      ),
                    ),
                    if (_shz == ShizukuState.noPermission)
                      FilledButton.tonal(
                        onPressed: _ensureShizuku,
                        child: const Text('Выдать разрешение'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pkg,
                      keyboardType: TextInputType.visiblePassword,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Пакет игры',
                        hintText: 'com.ggf.sf2',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _found = {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _xmlFile,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Файл',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (final k in XmlKind.values)
                                DropdownMenuItem(
                                  value: k.fileName,
                                  child: Text(
                                    _found.isEmpty
                                        ? k.fileName
                                        : '${k.fileName}  '
                                            '${_found.contains(k.fileName) ? '✓' : '✗'}',
                                  ),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _xmlFile = v ?? _xmlFile),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'Найти XML в gamedata',
                          icon: const Icon(Icons.search),
                          onPressed: _busy ? null : _scanFiles,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      isValidPackage(_pkgText)
                          ? _resolvedPath
                          : 'Введи корректное имя пакета',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _busy ? null : _open,
                    icon: const Icon(Icons.check),
                    label: Text(_busy ? 'Загрузка...' : 'Открыть файл'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
