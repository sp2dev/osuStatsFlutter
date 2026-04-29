import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils.dart';

class HistoryDetailPage extends StatefulWidget {
  final Map<String, dynamic> user;

  const HistoryDetailPage({super.key, required this.user});

  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  Map<String, dynamic>? _decodeModeJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final username = user['username'] as String;
    final modeJsons = [
      user['osu_json'],
      user['taiko_json'],
      user['fruits_json'],
      user['mania_json'],
    ];
    final modeData = modeJsons.map((e) => _decodeModeJson(e as String?)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(username),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetOsu.png')),
              text: 'osu!',
            ),
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetTaiko.png')),
              text: 'osu!taiko',
            ),
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetCatch.png')),
              text: 'osu!catch',
            ),
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetMania.png')),
              text: 'osu!mania',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: List.generate(4, (tabIndex) {
          final data = modeData[tabIndex];
          if (data == null) {
            return const Center(child: Text('暂无数据'));
          }
          final items = buildStatsItems(data);
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: () {
                  final icon = item['icon'];
                  if (icon is Widget) return icon;
                  return Icon(icon as IconData, size: 36);
                }(),
                title: Text(item['label'] as String,
                    style: const TextStyle(fontSize: 15)),
                subtitle: Text(item['value'] as String,
                    style: const TextStyle(fontSize: 25)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              );
            },
          );
        }),
      ),
    );
  }
}
