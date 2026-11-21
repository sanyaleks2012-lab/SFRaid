import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../common/feedback.dart';

class XmlEditScreen extends StatefulWidget {
  final XmlElement el;

  const XmlEditScreen(this.el, {super.key});

  @override
  State<XmlEditScreen> createState() => _XmlEditScreenState();
}

class _XmlEditScreenState extends State<XmlEditScreen> {
  late final TextEditingController _c =
      TextEditingController(text: ctrl.elementToXml(widget.el));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    try {
      ctrl.replaceElementXml(widget.el, _c.text);

      Navigator.of(context).pop(true);
    } on RaidForgeException catch (e) {
      toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('XML — ${widget.el.name.local}'),
        actions: [
          IconButton(
            tooltip: 'Применить',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          controller: _c,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
    );
  }
}
