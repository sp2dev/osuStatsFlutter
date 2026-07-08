import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osu_api_service.dart';
import '../services/database_service.dart';
import '../utils.dart';
import 'chart_page.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../core/constants.dart';

List<Map<String, dynamic>> _parseHistoryInBackground(List<Map<String, dynamic>> historyRaw) {
  return historyRaw.map((r) {
    Map<String, dynamic>? parse(String key) {
      final s = r[key] as String?;
      if (s != null && s.isNotEmpty) {
        try { return jsonDecode(s) as Map<String, dynamic>; } catch(_) {}
      }
      return null;
    }
    return {
      'id': r['id'],
      'updated_at': r['updated_at'],
      'osu_json': parse('osu_json'),
      'taiko_json': parse('taiko_json'),
      'fruits_json': parse('fruits_json'),
      'mania_json': parse('mania_json'),
    };
  }).toList();
}
class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}
class _MainPageState extends State<MainPage> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final TabController _tabController;
  final OsuApiService _apiService = OsuApiService();
  static const _modes = ['osu', 'taiko', 'fruits', 'mania'];
  final List<Map<String, dynamic>?> _modeData = [null, null, null, null];
  List<Map<String, dynamic>> _userHistory = [];
  List<Map<String, dynamic>> _parsedHistory = [];
  List<String> _userList = [];
  bool _isLoading = true;
  String? _error;
  String? _targetUser;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadAllData();
  }
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_modeData[_tabController.index] == null && _targetUser != null && !_isLoading) {
      _fetchModeData(_tabController.index);
    }
  }
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  Future<void> _loadAllData() async {
    final db = DatabaseService();
    final users = await db.getAllUsers();
    final uniqueNames = users.map((u) => u['username'] as String).toSet().toList()..sort();
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('query_username');
    if (username == null || username.isEmpty) {
      setState(() {
        _targetUser = null;
        _userList = uniqueNames;
        _isLoading = false;
        _error = null;
      });
      return;
    }
    _targetUser = username;
    _userList = uniqueNames;
    for (int i = 0; i < 4; i++) {
      _modeData[i] = null;
    }
    await _fetchModeData(_tabController.index);
    if (!mounted) return;
    final updatedUsers = await db.getAllUsers();
    final updatedNames = updatedUsers.map((u) => u['username'] as String).toSet().toList()..sort();
    if (!updatedNames.contains(username)) {
      updatedNames.insert(0, username);
    }
    setState(() {
      _userList = updatedNames;
    });
  }
  Future<void> _fetchModeData(int index) async {
    final username = _targetUser;
    if (username == null) return;
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getUserData(username, _modes[index]);
      if (mounted) {
        setState(() {
          _modeData[index] = data;
          _isLoading = false;
          _error = null;
        });
        _saveToDatabaseSingleMode(data, _modes[index]);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取 ${_modes[index]} 数据失败: $e';
          _isLoading = false;
        });
      }
    }
  }
  Future<void> _saveToDatabaseSingleMode(Map<String, dynamic>? data, String mode) async {
    if (data == null) return;
    final userId = data['id'] as int?;
    final username = data['username'] as String?;
    if (userId == null || username == null) return;
    final stats = data['statistics'] as Map<String, dynamic>?;
    if (stats == null || stats['play_count'] == null) {
      return; 
    }
    final db = DatabaseService();
    final modeKeyMap = {
      'osu': AppConstants.colOsuJson,
      'taiko': AppConstants.colTaikoJson,
      'fruits': AppConstants.colFruitsJson,
      'mania': AppConstants.colManiaJson,
    };
    final modeKey = modeKeyMap[mode]!;
    if (!(await db.hasModeChangedFromLatest(userId: userId, modeKey: modeKey, newData: data))) {
      final history = await db.getRecordsForUser(userId);
      final parsed = await compute(_parseHistoryInBackground, history);
      if (mounted) {
        setState(() {
          _userHistory = history;
          _parsedHistory = parsed;
        });
      }
      return; 
    }
    final latest = await db.getLatestRecord(userId);
    await db.saveUserData(
      userId: userId,
      username: username,
      countryCode: data['country_code'] as String?,
      beatmapPlaycountsCount: data['beatmap_playcounts_count'] as int?,
      followerCount: data['follower_count'] as int?,
      userAchievements: data['user_achievements'] as List?,
      osuJson: mode == 'osu' ? jsonEncode(data) : (latest?[AppConstants.colOsuJson] as String?),
      taikoJson: mode == 'taiko' ? jsonEncode(data) : (latest?[AppConstants.colTaikoJson] as String?),
      fruitsJson: mode == 'fruits' ? jsonEncode(data) : (latest?[AppConstants.colFruitsJson] as String?),
      maniaJson: mode == 'mania' ? jsonEncode(data) : (latest?[AppConstants.colManiaJson] as String?),
    );
    final history = await db.getRecordsForUser(userId);
    final parsed = await compute(_parseHistoryInBackground, history);
    if (mounted) {
      setState(() {
        _userHistory = history;
        _parsedHistory = parsed;
      });
      Provider.of<AppStateProvider>(context, listen: false).notifyHistoryUpdated();
    }
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hasUsers = _userList.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: !hasUsers
            ? Text(_targetUser ?? '主页面')
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _targetUser != null && _userList.contains(_targetUser)
                        ? _targetUser
                        : (_userList.isNotEmpty ? _userList.first : null),
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    onChanged: (String? newValue) async {
                      if (newValue != null && newValue != _targetUser) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('query_username', newValue);
                        _loadAllData();
                      }
                    },
                    items: _userList.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ),
              ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetOsu.png'), size: 24),
              text: 'osu!',
            ),
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetTaiko.png'), size: 24),
              text: 'osu!taiko',
            ),
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetCatch.png'), size: 24),
              text: 'osu!catch',
            ),
            Tab(
              icon: ImageIcon(AssetImage('assets/Rulesets/RulesetMania.png'), size: 24),
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
    if (_targetUser == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 24),
              Text(
                '欢迎使用 osu! Stats',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '请前往 设置 - API 凭据设置 添加 API 凭据和查询用户名以开始',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    if (_isLoading) {
      return _buildSkeleton();
    }
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadAllData,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final compareTarget = provider.compareTarget;
        return TabBarView(
          controller: _tabController,
          children: List.generate(4, (tabIndex) {
            final data = _modeData[tabIndex];
            if (data == null) {
              return const Center(child: Text('暂无数据'));
            }
            Map<String, dynamic>? prevData;
            final modeKeys = ['osu_json', 'taiko_json', 'fruits_json', 'mania_json'];
            final modeKey = modeKeys[tabIndex];
            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
            Map<String, dynamic>? findLastQuery() {
              for (final record in _parsedHistory) {
                final histData = record[modeKey] as Map<String, dynamic>?;
                if (histData != null) {
                  if (areStatsDifferent(data, histData)) {
                    return histData;
                  }
                }
              }
              return null;
            }
            if (compareTarget == CompareTarget.lastQuery) {
              prevData = findLastQuery();
            } else if (compareTarget == CompareTarget.todayEarliest) {
              Map<String, dynamic>? earliestToday;
              for (final record in _parsedHistory) {
                final updatedAt = record['updated_at'] as int;
                if (updatedAt >= todayStart) {
                  final histData = record[modeKey] as Map<String, dynamic>?;
                  if (histData != null) {
                    if (areStatsDifferent(data, histData)) {
                      earliestToday = histData;
                    } else {
                      earliestToday = histData;
                    }
                  }
                } else {
                  break;
                }
              }
              if (earliestToday != null && !areStatsDifferent(data, earliestToday)) {
                earliestToday = null;
              }
              prevData = earliestToday ?? findLastQuery();
            } else if (compareTarget == CompareTarget.yesterdayLatest) {
              Map<String, dynamic>? latestYesterday;
              for (final record in _parsedHistory) {
                final updatedAt = record['updated_at'] as int;
                if (updatedAt < todayStart) {
                  final histData = record[modeKey] as Map<String, dynamic>?;
                  if (histData != null) {
                    latestYesterday = histData;
                    break;
                  }
                }
              }
              if (latestYesterday != null && !areStatsDifferent(data, latestYesterday)) {
                latestYesterday = null;
              }
              prevData = latestYesterday ?? findLastQuery();
            }
            final items = buildStatsItems(data, prevData);
        return RefreshIndicator(
          onRefresh: _loadAllData,
          child: AnimationLimiter(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return AnimationConfiguration.staggeredList(
                  position: index,
                  duration: const Duration(milliseconds: 375),
                  child: SlideAnimation(
                    verticalOffset: 50.0,
                    child: FadeInAnimation(
                      child: Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (_userHistory.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChartPage(
                          username: _targetUser ?? '',
                          statLabel: item['label'] as String,
                          fieldKey: item['fieldKey'] as String,
                          modeKey: modeKey,
                          history: _userHistory,
                        ),
                      ),
                    );
                  },
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
                ),
              ),
            ),
          ),
        );
              },
            ),
          ),
        );
      }),
    );
      },
    );
  }
  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      highlightColor: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Container(
            height: 80,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }
}
