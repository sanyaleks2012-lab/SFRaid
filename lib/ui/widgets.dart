import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/l10n.dart';
import '../core/raid_controller.dart';
import '../core/xml_utils.dart';
import '../lua/plugin_host.dart';

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
}

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

class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final VoidCallback? onEdit;
  final Widget? action;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.onEdit,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: cs.secondaryContainer.withValues(alpha: 0.25),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (action != null) action!,
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                  ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      );
}

class FieldSpec {
  final String key;
  final String label;
  final String value;
  final bool numeric;
  const FieldSpec(this.key, this.label, this.value, {this.numeric = false});
}

/// Нижний лист с полями. Возвращает значения по key или null при отмене.
Future<Map<String, String>?> showFieldsSheet(
  BuildContext context,
  String title,
  List<FieldSpec> fields, {
  String? hint,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _FieldsSheet(title: title, fields: fields, hint: hint),
  );
}

class _FieldsSheet extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final String? hint;
  const _FieldsSheet({required this.title, required this.fields, this.hint});

  @override
  State<_FieldsSheet> createState() => _FieldsSheetState();
}

class _FieldsSheetState extends State<_FieldsSheet> {
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

  void _submit() {
    Navigator.pop(context, {
      for (final f in widget.fields) f.key: _c[f.key]!.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          if (widget.hint != null) ...[
            const SizedBox(height: 6),
            Text(widget.hint!,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          const SizedBox(height: 12),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _c[f.key],
                keyboardType: f.numeric
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                autocorrect: false,
                decoration: InputDecoration(labelText: f.label),
                onSubmitted: (_) => _submit(),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('common.cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(tr('common.ok')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Сохранение с backup, хуком onSave, тактильным откликом и сообщением.
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
    if (context.mounted) {
      snack(context, tr('toast.backup', {'path': backup}));
    }
  } catch (e) {
    if (context.mounted) {
      snack(context, tr('err.saveFailed', {'error': '$e'}));
    }
  }
}

/// Шорткат для обработки RaidForgeException в обработчиках UI.
void guard(BuildContext context, void Function() action) {
  try {
    action();
  } on RaidForgeException catch (e) {
    snack(context, e.message);
  }
}