import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/xml_helpers.dart';
import '../boss/boss_screen.dart';
import '../common/navigation.dart';
import '../common/widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final res = ctrl.searchBosses(q.trim());

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Name / Alias / Title / Template / Location',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => q = v),
        ),
      ),
      body: q.trim().isEmpty
          ? emptyNote('Введите запрос')
          : res.isEmpty
              ? emptyNote('Ничего не найдено.')
              : ListView(
                  children: [
                    for (final (zone, battle) in res)
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(battle.attr('Name', '?')),
                        subtitle: Text(
                          '[${zone.attr('Name', '?')}] '
                          '${battle.attr('Title')}',
                        ),
                        onTap: () => go(
                          context,
                          BossScreen(battle),
                        ),
                      ),
                  ],
                ),
    );
  }
}
