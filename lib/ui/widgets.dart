import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../lua/plugin_host.dart';
import '../core/xml_utils.dart';

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
}

void goTo(BuildContext context, Widget w) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

Widget emptyNote(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      ),
    );

Future<bool> confirmDialog(BuildContext context, String message) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(tr('common.no')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr('common.yes')),
        ),
      ],
    ),
  );
  return r ?? false;
}

class FieldSpec {
  final String key;
  final String label;
  final String value;
  final bool numeric;
  const FieldSpec(this.key, this.label, this.value, {this.numeric = false});
}

/// Диалог с полями (AlertDialog). Возвращает значения по key или null при отмене.
Future<Map<String, String>?> showFieldsSheet(
  BuildContext context,
  String title,
  List<FieldSpec> fields, {
  String? hint,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _FormDialog(title: title, fields: fields, hint: hint),
  );
}

class _FormDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final String? hint;
  const _FormDialog({required this.title, required this.fields, this.hint});

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.value),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ok() {
    Navigator.pop(context, {
      for (final f in widget.fields) f.key: _c[f.key]!.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.hint != null) ...[
              Text(widget.hint!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
            ],
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _c[f.key],
                  autocorrect: false,
                  keyboardType: f.numeric
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  decoration: InputDecoration(labelText: f.label),
                  onSubmitted: (_) => _ok(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('common.cancel')),
        ),
        FilledButton(onPressed: _ok, child: Text(tr('common.ok'))),
      ],
    );
  }
}

/// Список выбора (AlertDialog). Возвращает индекс или null.
Future<int?> pick(BuildContext context, String title, List<String> items) {
  return showDialog<int>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: ListView.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => ListTile(
            dense: true,
            title: Text(items[i]),
            onTap: () => Navigator.pop(c, i),
          ),
        ),
      ),
    ),
  );
}

Future<void> saveWithFeedback(
    BuildContext context, RaidForgeController ctrl) async {
  if (!ctrl.dirty) {
    snack(context, tr('err.noChanges'));
    return;
  }
  try {
    pluginHost.fire('onSave');
    final backup = await ctrl.save();
    HapticFeedback.mediumImpact();
    if (context.mounted) snack(context, tr('toast.backup', {'path': backup}));
  } catch (e) {
    if (context.mounted) snack(context, tr('err.saveFailed', {'error': '$e'}));
  }
}

void guard(BuildContext context, void Function() action) {
  try {
    action();
  } on RaidForgeException catch (e) {
    snack(context, e.message);
  }
}