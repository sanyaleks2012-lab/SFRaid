import 'package:flutter/material.dart';

Widget tile(
  IconData icon,
  String title, {
  String? sub,
  VoidCallback? onTap,
  Widget? trailing,
}) {
  return ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: sub == null ? null : Text(sub),
    trailing: trailing ??
        (onTap != null ? const Icon(Icons.chevron_right) : null),
    onTap: onTap,
  );
}

Widget emptyNote(String text) {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey),
      ),
    ),
  );
}
