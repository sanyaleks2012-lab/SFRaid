import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import 'feedback.dart';

Widget editorBottomBar(BuildContext context) {
  return BottomAppBar(
    height: 64,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Отменить (${ctrl.undoCount}/$maxUndo)',
          icon: Badge(
            isLabelVisible: ctrl.undoCount > 0,
            label: Text('${ctrl.undoCount}'),
            child: const Icon(Icons.undo),
          ),
          onPressed: () {
            if (!ctrl.undo()) toast(context, 'История изменений пуста.');
          },
        ),
        IconButton(
          tooltip: 'Сохранить + backup',
          icon: const Icon(Icons.save),
          onPressed: () => doSave(context),
        ),
        const Spacer(),
        Text(
          ctrl.dirty ? 'Есть изменения' : 'Сохранено',
          style: TextStyle(
            fontSize: 11,
            color: ctrl.dirty ? Colors.amber : Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
  );
}
