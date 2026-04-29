import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'history_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final DatabaseService _db = DatabaseService();

  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _selectedUsername;

  List<String> get _uniqueUsernames {
    return _users
        .map((u) => u['username'] as String)
        .toSet()
        .toList()
      ..sort();
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_selectedUsername == null) return _users;
    return _users
        .where((u) => u['username'] == _selectedUsername)
        .toList();
  }

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
      if (_selectedUsername != null &&
          !_users.any((u) => u['username'] == _selectedUsername)) {
        _selectedUsername = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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

    final filtered = _filteredUsers;

    return Column(
      children: [
        SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: DropdownButton<String>(
            value: _selectedUsername,
            isExpanded: true,
            hint: const Text('全部玩家'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('全部玩家', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ..._uniqueUsernames.map(
                (name) => DropdownMenuItem<String>(
                  value: name,
                  child: Text(name),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _selectedUsername = value);
            },
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text('$_selectedUsername 暂无记录',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      final updatedAt = user['updated_at'] as int;
                      final dateStr = DateTime.fromMillisecondsSinceEpoch(updatedAt)
                          .toString()
                          .substring(0, 16)
                          .replaceFirst('T', ' ');

                      return Dismissible(
                        key: Key('record_${user['id']}'),
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
                              content:
                                  Text('删除 ${user['username']} 的缓存数据？'),
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
                          _db.deleteRecord(user['id'] as int);
                          _loadUsers();
                        },
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(user['username']
                                .toString()[0]
                                .toUpperCase()),
                          ),
                          title: Text(user['username'] as String),
                          subtitle: Text('更新于 $dateStr'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    HistoryDetailPage(user: user),
                              ),
                            );
                            _loadUsers();
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
