import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osu_api_service.dart';
import '../services/database_service.dart';
import '../utils.dart';

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

    final results = await Future.wait(
      _modes.map((mode) async {
        try {
          return await _apiService.getUserData(username, mode);
        } catch (e) {
          return null;
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      for (int i = 0; i < results.length; i++) {
        _modeData[i] = results[i];
      }
      _isLoading = false;
    });

    _saveToDatabase(results);
  }

  Future<void> _saveToDatabase(List<Map<String, dynamic>?> results) async {
    Map<String, dynamic>? firstSuccess;
    for (final r in results) {
      if (r != null) {
        firstSuccess = r;
        break;
      }
    }
    if (firstSuccess == null) return;

    final userId = firstSuccess['id'] as int?;
    final username = firstSuccess['username'] as String?;
    if (userId == null || username == null) return;

    final db = DatabaseService();
    final changed = await db.hasChangedFromLatest(
      userId: userId,
      osuData: results[0],
      taikoData: results[1],
      fruitsData: results[2],
      maniaData: results[3],
    );
    if (!changed) return;

    await db.saveUserData(
      userId: userId,
      username: username,
      countryCode: firstSuccess['country_code'] as String?,
      beatmapPlaycountsCount:
          firstSuccess['beatmap_playcounts_count'] as int?,
      followerCount: firstSuccess['follower_count'] as int?,
      userAchievements: firstSuccess['user_achievements'] as List?,
      osuJson: results[0] != null ? jsonEncode(results[0]) : null,
      taikoJson: results[1] != null ? jsonEncode(results[1]) : null,
      fruitsJson: results[2] != null ? jsonEncode(results[2]) : null,
      maniaJson: results[3] != null ? jsonEncode(results[3]) : null,
    );
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
        final items = buildStatsItems(data);
        return RefreshIndicator(
          onRefresh: _loadAllData,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: () {
                  final icon = item['icon'];
                  if (icon is Widget) return icon;
                  return Icon(icon as IconData, size: 36);
                }(),
                title: Text(item['label'] as String, style: TextStyle(fontSize: 15),),
                subtitle: Text(item['value'] as String, style: TextStyle(fontSize: 25),),
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
