import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osu_api_service.dart';
import '../services/database_service.dart';
import '../utils.dart';
import 'chart_page.dart';

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
  List<Map<String, dynamic>> _userHistory = [];
  List<String> _userList = [];
  bool _isLoading = true;
  String? _error;
  String? _targetUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
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
        _error = uniqueNames.isNotEmpty
            ? '请在顶部选择用户或先到"设置"页面输入用户名'
            : '请先到"设置"页面输入用户名再查询';
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

    List<Map<String, dynamic>> userHistory = [];
    Map<String, dynamic>? firstSuccess;
    for (final r in results) {
      if (r != null) {
        firstSuccess = r;
        break;
      }
    }
    if (firstSuccess != null) {
      final userId = firstSuccess['id'] as int?;
      if (userId != null) {
        userHistory = await DatabaseService().getRecordsForUser(userId);
      }
    }

    // Refresh user list in case a new user was queried
    final updatedUsers = await db.getAllUsers();
    final updatedNames = updatedUsers.map((u) => u['username'] as String).toSet().toList()..sort();
    if (!updatedNames.contains(username)) {
      updatedNames.insert(0, username);
    }

    setState(() {
      for (int i = 0; i < results.length; i++) {
        _modeData[i] = results[i];
      }
      _userHistory = userHistory;
      _userList = updatedNames;
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
  Widget build(BuildContext context) {
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
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

    return ValueListenableBuilder<CompareTarget>(
      valueListenable: compareTargetNotifier,
      builder: (context, compareTarget, _) {
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
              for (final record in _userHistory) {
                final jsonStr = record[modeKey] as String?;
                if (jsonStr != null && jsonStr.isNotEmpty) {
                  try {
                    final histData = jsonDecode(jsonStr) as Map<String, dynamic>;
                    if (areStatsDifferent(data, histData)) {
                      return histData;
                    }
                  } catch (_) {}
                }
              }
              return null;
            }

            if (compareTarget == CompareTarget.lastQuery) {
              prevData = findLastQuery();
            } else if (compareTarget == CompareTarget.todayEarliest) {
              Map<String, dynamic>? earliestToday;
              for (final record in _userHistory) {
                final updatedAt = record['updated_at'] as int;
                if (updatedAt >= todayStart) {
                  final jsonStr = record[modeKey] as String?;
                  if (jsonStr != null && jsonStr.isNotEmpty) {
                    try {
                      final histData = jsonDecode(jsonStr) as Map<String, dynamic>;
                      if (areStatsDifferent(data, histData)) {
                        earliestToday = histData;
                      } else {
                        // If it's identical, we keep looking further back in today's records
                        // (though earliest will just overwrite). But actually we want the
                        // absolute earliest today. So we should just update earliestToday.
                        earliestToday = histData;
                      }
                    } catch (_) {}
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
              for (final record in _userHistory) {
                final updatedAt = record['updated_at'] as int;
                if (updatedAt < todayStart) {
                  final jsonStr = record[modeKey] as String?;
                  if (jsonStr != null && jsonStr.isNotEmpty) {
                    try {
                      latestYesterday = jsonDecode(jsonStr) as Map<String, dynamic>;
                      break;
                    } catch (_) {}
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
          child: ListView.builder(
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
              ));
            },
          ),
        );
      }),
    );
      },
    );
  }
}
