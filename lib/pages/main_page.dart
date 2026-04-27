import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osu_api_service.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final OsuApiService _apiService = OsuApiService();

  static const _modes = ['osu', 'taiko', 'fruits', 'mania'];

  final List<Map<String, dynamic>?> _modeData = [null, null, null, null];
  bool _isLoading = true;
  String? _error;
  String? _targetUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('query_username');
    if (username == null || username.isEmpty) {
      setState(() {
        _targetUser = null;
        _isLoading = false;
        _error = '请先到"设置"页面输入用户名再查询';
      });
      return;
    }

    _targetUser = username;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final results = <Map<String, dynamic>?>[];
    for (final mode in _modes) {
      try {
        final data = await _apiService.getUserData(username, mode);
        results.add(data);
      } catch (e) {
        results.add(null);
      }
    }

    if (!mounted) return;
    setState(() {
      for (int i = 0; i < results.length; i++) {
        _modeData[i] = results[i];
      }
      _isLoading = false;
    });
  }

  String _formatNum(dynamic val) {
    if (val == null) return '-';
    final str = val is int ? val.toString() : val.toString();
    if (str.isEmpty) return '-';
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  List<Map<String, dynamic>> _buildItems(Map<String, dynamic> data) {
    final stats = data['statistics'] as Map<String, dynamic>? ?? {};

    final accuracy = stats['accuracy'] as num?;
    final accuracyStr = accuracy != null
        ? '${(accuracy * 100).toStringAsFixed(2)}%'
        : '-';

    final globalRank = stats['global_rank'];
    final countryRank = stats['country_rank'];

    return [
      {'label': 'pp', 'value': _formatNum(stats['pp'])},
      {
        'label': '排名',
        'value': globalRank != null ? '#${_formatNum(globalRank)}' : '-'
      },
      {
        'label': '地区排名',
        'value': countryRank != null ? '#${_formatNum(countryRank)}' : '-'
      },
      {'label': '准确率', 'value': accuracyStr},
      {'label': '总击打次数', 'value': _formatNum(stats['total_hits'])},
      {'label': '计分成绩总分', 'value': _formatNum(stats['ranked_score'])},
      {'label': '总分数', 'value': _formatNum(stats['total_score'])},
      {'label': '游玩次数', 'value': _formatNum(stats['play_count'])},
      {
        'label': '已游玩的谱面数量',
        'value': _formatNum(data['beatmap_playcounts_count'])
      },
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_targetUser != null ? _targetUser! : '主页面'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [

            // TODO: 这里的图标需要替换成 osu! 四个模式的图标

            Tab(icon: Icon(Icons.circle), text: 'osu!'),
            Tab(icon: Icon(Icons.circle), text: 'osu!taiko'),
            Tab(icon: Icon(Icons.circle), text: 'osu!catch'),
            Tab(icon: Icon(Icons.circle), text: 'osu!mania'),

            // Tab(icon: _tabIcon("assets/Rulesets/RulesetOsu.png"), text: 'osu!'),
            // Tab(icon: _tabIcon("assets/Rulesets/RulesetTaiko.png"), text: 'osu!taiko'),
            // Tab(icon: _tabIcon("assets/Rulesets/RulesetCatch.png"), text: 'osu!catch'),
            // Tab(icon: _tabIcon("assets/Rulesets/RulesetMania.png"), text: 'osu!mania'),
          ],
        ),
      ),
      body: _buildBody(),
      floatingActionButton: _targetUser != null
          ? FloatingActionButton.small(
              onPressed: _loadAllData,
              child: const Icon(Icons.refresh),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadAllData,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: List.generate(4, (tabIndex) {
        final data = _modeData[tabIndex];
        if (data == null) {
          return const Center(child: Text('暂无数据'));
        }
        final items = _buildItems(data);
        return RefreshIndicator(
          onRefresh: _loadAllData,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: const Icon(Icons.music_note, size: 36),
                title: Text(item['label'] as String),
                subtitle: Text(item['value'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              );
            },
          ),
        );
      }),
    );
  }
}

// Widget _tabIcon(String asset) {
//   return Image.asset(asset, width: 28, height: 28, fit: BoxFit.contain);
// }
