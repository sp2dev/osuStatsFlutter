import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
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
  Map<String, dynamic>? _previousRecord;

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
    _loadPreviousRecord();
  }

  Future<void> _loadPreviousRecord() async {
    final userId = widget.user['user_id'] as int?;
    final updatedAt = widget.user['updated_at'] as int?;
    if (userId != null && updatedAt != null) {
      final prev = await DatabaseService().getPreviousRecord(userId, updatedAt);
      if (!mounted) return;
      setState(() {
        _previousRecord = prev;
      });
    }
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

    final prevModeJsons = _previousRecord != null
        ? [
            _previousRecord!['osu_json'],
            _previousRecord!['taiko_json'],
            _previousRecord!['fruits_json'],
            _previousRecord!['mania_json'],
          ]
        : [null, null, null, null];
    final prevModeData = prevModeJsons.map((e) => _decodeModeJson(e as String?)).toList();

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
          final prevData = prevModeData[tabIndex];
          if (data == null) {
            return const Center(child: Text('暂无数据'));
          }
          final items = buildStatsItems(data, prevData);
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
                trailing: () {
                  final diff = item['difference'];
                  if (diff != null) {
                    final diffText = diff['text'] as String;
                    final isPositive = diff['isPositive'] as bool;
                    return Text(
                      diffText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green : Colors.red,
                      ),
                    );
                  }
                  return null;
                }(),
                onTap: () {},
              );
            },
          );
        }),
      ),
    );
  }
}
