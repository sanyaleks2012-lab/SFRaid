import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_state.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../core/storage.dart';
import '../core/xml_utils.dart';
import '../core/shizuku_bridge.dart';
import 'quests_screens.dart';
import '../lua/plugin_host.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

enum AccessMode { direct, shizuku }

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final _path = TextEditingController(text: '/storage/emulated/0/raid_stages_default.xml');
  final _pkg = TextEditingController(text: 'com.ggf.sf2');

  AccessMode _mode = AccessMode.direct;
  ShizukuState _shz = ShizukuState.notInstalled;
  Set<String> _found = {};
  String _xmlFile = XmlKind.raid.fileName;
  List<String> _recent = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadRecentPackages().then((r) {
      if (mounted) setState(() => _recent = r);
    });
    _refreshShizuku();
  }

  @override
  void dispose() {
    _path.dispose();
    _pkg.dispose();
    super.dispose();
  }

  String get _resolved => _mode == AccessMode.shizuku
      ? '${gamedataDir(_pkg.text.trim())}/$_xmlFile'
      : _path.text.trim();

  String get _shizukuLabel => switch (_shz) {
        ShizukuState.notInstalled => tr('start.shizuku.notInstalled'),
        ShizukuState.notRunning => tr('start.shizuku.notRunning'),
        ShizukuState.noPermission => tr('start.shizuku.noPermission'),
        ShizukuState.ready => tr('start.shizuku.ready'),
      };

  Future<void> _refreshShizuku() async {
    try {
      final s = await ShizukuBridge.state();
      if (mounted) setState(() => _shz = s);
    } catch (_) {}
  }

  Future<bool> _ensureShizuku() async {
    await _refreshShizuku();
    if (_shz == ShizukuState.noPermission) {
      await ShizukuBridge.requestPermission();
      await _refreshShizuku();
    }
    if (_shz != ShizukuState.ready && mounted) snack(context, _shizukuLabel);
    return _shz == ShizukuState.ready;
  }

  Future<void> _scan() async {
    final pkg = _pkg.text.trim();
    if (!isValidPackage(pkg)) {
      snack(context, tr('start.invalidPackage'));
      return;
    }
    if (!await _ensureShizuku()) return;
    try {
      final all = await ShizukuBridge.list(gamedataDir(pkg));
      final found = {
        for (final k in XmlKind.values)
          if (all.contains(k.fileName)) k.fileName,
      };
      if (!mounted) return;
      setState(() {
        _found = found;
        if (found.isNotEmpty && !found.contains(_xmlFile)) {
          _xmlFile = found.first;
        }
      });
      if (found.isEmpty && mounted) {
        snack(context, tr('start.noFilesInGamedata'));
      }
    } catch (e) {
      if (mounted) snack(context, tr('err.readFailed', {'error': '$e'}));
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
    );
    final p = r?.files.single.path;
    if (p == null || !mounted) return;
    if (XmlKind.fromPath(p) == null) {
      snack(context, tr('start.noFiles', {'allowed': XmlKind.allowedList}));
      return;
    }
    setState(() => _path.text = p);
  }

  void _setDirectFile(XmlKind k) {
    setState(() => _path.text = '${dirOf(_path.text.trim())}/${k.fileName}');
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final RaidIo io;
      if (_mode == AccessMode.shizuku) {
        final pkg = _pkg.text.trim();
        if (!isValidPackage(pkg)) {
          snack(context, tr('start.invalidPackage'));
          return;
        }
        if (!await _ensureShizuku()) return;
        io = ShizukuIo();
        await rememberPackage(pkg);
      } else {
        if (!await requestAllFilesAccess()) {
          if (!mounted) return;
          snack(context, tr('start.grantAccess'));
          await openAppSettings();
          return;
        }
        io = DirectIo();
      }

      final path = _resolved;
      final kind = XmlKind.fromPath(path);
      if (kind == null) {
        if (mounted) {
          snack(context, tr('start.noFiles', {'allowed': XmlKind.allowedList}));
        }
        return;
      }

      final c = RaidForgeController(path, io, kind);
      await c.load();

            await c.reloadPerks(appState.perkMode);
      await pluginHost.reload(c);

      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => kind == XmlKind.quests
            ? QuestsHomeScreen(ctrl: c)
            : HomeScreen(ctrl: c),
      ));
    } on RaidForgeException catch (e) {
      if (mounted) snack(context, e.message);
    } catch (e) {
      if (mounted) snack(context, tr('err.readFailed', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shizuku = _mode == AccessMode.shizuku;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('app.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr('home.settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<AccessMode>(
                  segments: [
                    ButtonSegment(
                      value: AccessMode.direct,
                      icon: const Icon(Icons.folder),
                      label: Text(tr('start.mode.files')),
                    ),
                    ButtonSegment(
                      value: AccessMode.shizuku,
                      icon: const Icon(Icons.adb),
                      label: Text(tr('start.mode.shizuku')),
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
                      labelText: '${tr('start.path')} (${XmlKind.allowedList})',
                      suffixIcon: IconButton(
                        tooltip: tr('start.pick'),
                        icon: const Icon(Icons.folder_open),
                        onPressed: _busy ? null : _pick,
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
                    onPressed: _busy ? null : requestAllFilesAccess,
                    icon: const Icon(Icons.lock_open),
                    label: Text(tr('start.grantAccess')),
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
                      child: Text(tr('start.shizuku.grant')),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pkg,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: tr('start.package'),
                      hintText: 'com.ggf.sf2',
                    ),
                    onChanged: (_) => setState(() => _found = {}),
                  ),
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final p in _recent)
                          ActionChip(
                            label: Text(p),
                            onPressed: () => setState(() {
                              _pkg.text = p;
                              _found = {};
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _xmlFile,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: tr('start.path')),
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
                        tooltip: tr('start.scan'),
                        icon: const Icon(Icons.search),
                        onPressed: _busy ? null : _scan,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    isValidPackage(_pkg.text.trim())
                        ? _resolved
                        : tr('start.invalidPackage'),
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
                  label: Text(_busy ? tr('start.loading') : tr('start.open')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}