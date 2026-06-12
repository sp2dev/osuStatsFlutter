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

  String get _pageTitle => _selectedUsername ?? '全部玩家';

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
        child: Padding(
          // padding: const EdgeInsets.symmetric(horizontal: 24),
          padding: MediaQuery.of(context).padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history,
                  size: 40,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '暂无历史记录',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                '查询过的用户数据会保存在这里，之后可以快速回看。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredUsers;

    return Container(
      padding: MediaQuery.of(context).padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
            Theme.of(context).colorScheme.surface,
          ],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _loadUsers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.secondary,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.history, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '历史记录',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '保存最近查询过的玩家，支持快速筛选和回看。',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InfoChip(label: '记录数', value: '${_users.length}'),
                      _InfoChip(label: '当前筛选', value: _pageTitle),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: DropdownButtonFormField<String?>(
                  initialValue: _selectedUsername,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '筛选玩家',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('全部玩家'),
                    ),
                    ..._uniqueUsernames.map(
                      (name) => DropdownMenuItem<String?>(
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
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 52,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$_pageTitle 暂无记录',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filtered.map((user) {
                final updatedAt = user['updated_at'] as int;
                final dateStr = DateTime.fromMillisecondsSinceEpoch(updatedAt)
                    .toString()
                    .substring(0, 16)
                    .replaceFirst('T', ' ');
                final username = user['username'] as String;
                final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Dismissible(
                    key: Key('record_${user['id']}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('确认删除'),
                          content: Text('删除 $username 的缓存数据？'),
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
                    child: Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HistoryDetailPage(user: user),
                            ),
                          );
                          _loadUsers();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor:
                                    Theme.of(context).colorScheme.primaryContainer,
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      username,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '更新于 $dateStr',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
              ),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
