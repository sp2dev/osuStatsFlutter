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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconTheme(
                          data: IconThemeData(
                            color: Theme.of(context).colorScheme.primary,
                            size: 28,
                          ),
                          child: () {
                            final icon = item['icon'];
                            if (icon is Widget) return icon;
                            return Icon(icon as IconData);
                          }(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['label'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['value'] as String,
                              style: TextStyle(
                                fontSize: 20,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      () {
                        final diff = item['difference'];
                        if (diff != null) {
                          final diffText = diff['text'] as String;
                          final isPositive = diff['isPositive'] as bool;
                          final baseColor = isPositive ? Colors.green : Colors.red;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: baseColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: baseColor.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              diffText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: baseColor,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      }(),
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
