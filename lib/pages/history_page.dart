import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../utils.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();

  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  Map<String, dynamic>? _selectedUser;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final users = await _db.getAllUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  void _openUser(Map<String, dynamic> user) {
    _tabController?.dispose();
    _tabController = TabController(length: 4, vsync: this);
    setState(() => _selectedUser = user);
  }

  void _closeDetail() {
    _tabController?.dispose();
    _tabController = null;
    setState(() => _selectedUser = null);
    _loadUsers();
  }

  Map<String, dynamic>? _decodeModeJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedUser != null) {
      return _buildDetailView();
    }
    return _buildUserList();
  }

  Widget _buildUserList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('暂无历史记录', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text('查询过的用户数据会保存在这里',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          final updatedAt = user['updated_at'] as int;
          final dateStr = DateTime.fromMillisecondsSinceEpoch(updatedAt)
              .toString()
              .substring(0, 16)
              .replaceFirst('T', ' ');

          return Dismissible(
            key: Key('user_${user['user_id']}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('确认删除'),
                  content: Text('删除 ${user['username']} 的缓存数据？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
            },
            onDismissed: (_) {
              _db.deleteUser(user['user_id'] as int);
              _loadUsers();
            },
            child: ListTile(
              leading: CircleAvatar(
                child: Text(user['username'].toString()[0].toUpperCase()),
              ),
              title: Text(user['username'] as String),
              subtitle: Text('更新于 $dateStr'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openUser(user),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailView() {
    final user = _selectedUser!;
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeDetail,
        ),
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
