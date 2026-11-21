import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/xml_helpers.dart';

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c).showSnackBar(
    SnackBar(content: Text(m)),
  );
}

void guard(BuildContext c, void Function() action) {
  try {
    action();
  } on RaidForgeException catch (e) {
    toast(c, e.message);
  }
}

Future<void> doSave(BuildContext context) async {
  if (!ctrl.dirty) {
    toast(context, 'Нет изменений для сохранения.');
    return;
  }

  try {
    final b = await ctrl.save();

    if (context.mounted) {
      toast(context, 'XML сохранён. Backup: $b');
    }
  } catch (e) {
    if (context.mounted) {
      toast(context, 'Ошибка сохранения: $e');
    }
  }
}
