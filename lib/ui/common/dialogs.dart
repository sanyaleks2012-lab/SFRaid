import 'package:flutter/material.dart';

Future<bool> confirm(BuildContext c, String msg) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (x) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(x, false),
          child: const Text('Нет'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(x, true),
          child: const Text('Да'),
        ),
      ],
    ),
  );

  return r ?? false;
}

Future<Map<String, String>?> form(
  BuildContext c,
  String title,
  Map<String, String> fields, {
  String hint = '',
}) {
  final ctrls = {
    for (final e in fields.entries)
      e.key: TextEditingController(text: e.value),
  };

  return showDialog<Map<String, String>>(
    context: c,
    builder: (x) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
            for (final e in ctrls.entries)
              TextField(
                controller: e.value,
                decoration: InputDecoration(labelText: e.key),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(x),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(x, {
            for (final e in ctrls.entries)
              e.key: e.value.text.trim(),
          }),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<int?> pick(
  BuildContext c,
  String title,
  List<String> items,
) {
  return showDialog<int>(
    context: c,
    builder: (x) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (_, i) => ListTile(
            dense: true,
            title: Text(items[i]),
            onTap: () => Navigator.pop(x, i),
          ),
        ),
      ),
    ),
  );
}
