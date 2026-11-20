import 'package:flutter/material.dart';
import 'app_state.dart';
import 'core/l10n.dart';
import 'core/storage.dart';
import 'ui/start_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await requestAllFilesAccess();
  try {
    await ensureLayout();
  } catch (_) {
    // Без доступа к хранилищу приложение всё равно запустится.
  }
  await appState.load();
  await L10n.load(appState.lang);
  runApp(const RaidForgeApp());
}

class RaidForgeApp extends StatelessWidget {
  const RaidForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => MaterialApp(
        // Смена языка пересоздаёт приложение, поэтому ключ меняется вместе с языком.
        key: ValueKey(appState.lang),
        title: tr('app.title'),
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const StartScreen(),
      ),
    );
  }
}