import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../core/session.dart';

class XmlViewScreen extends StatelessWidget {
  final XmlElement el;

  const XmlViewScreen(this.el, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XML VIEW'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            ctrl.elementToXml(el),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
