import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../services/osu_api_service.dart';
import '../services/database_service.dart';
import '../services/widget_data_service.dart';
import '../utils.dart';

class WidgetConfigPage extends StatefulWidget {
  /// When non-null, this config page is for an existing widget (e.g., tapped from home screen).
  final int? initialWidgetId;

  const WidgetConfigPage({super.key, this.initialWidgetId});

  @override
  State<WidgetConfigPage> createState() => _WidgetConfigPageState();
}

class _WidgetConfigPageState extends State<WidgetConfigPage> {
  final WidgetDataService _widgetService = WidgetDataService();

  static const _timeRanges = ['1天', '3天', '7天', '1个月', '自定义'];

  final _usernameController = TextEditingController();
  final _customDaysController = TextEditingController();

  List<String> _userList = [];
  bool _isLoading = true;
  bool _isSaving = false;

  String? _selectedUsername;
  String _selectedMode = 'osu';
  String _selectedFieldKey = 'pp';
  String _selectedFieldLabel = 'pp';
  String _selectedTimeRange = '7天';
  int _customDays = 0;

  List<Map<String, dynamic>> get _statOptions {
    final mockData = {
      'statistics': {
        'pp': 0,
        'global_rank': 0,
        'country_rank': 0,
        'accuracy': 0.0,
        'total_hits': 0,
        'ranked_score': 0,
        'total_score': 0,
        'play_count': 0,
        'play_time': 0,
      },
    };
    return buildStatsItems(mockData);
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final db = DatabaseService();
      final users = await db.getAllUsers();
      final names = users.map((u) => u['username'] as String).toSet().toList()
        ..sort();
      if (!mounted) return;
      setState(() {
        _userList = names;
        _isLoading = false;
        if (_userList.isNotEmpty && _selectedUsername == null) {
          _selectedUsername = _userList.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  bool get _isFormValid =>
      _selectedUsername != null && _selectedUsername!.trim().isNotEmpty;

  bool get _isFromWidgetTap => widget.initialWidgetId != null;

  Future<void> _onSave() async {
    if (!_isFormValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择或输入要查询的玩家')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final username = _selectedUsername!.trim();
      final modeKey = _widgetService.modeDisplayToKey(_selectedMode);

      // Try to validate by fetching data
      try {
        final api = OsuApiService();
        await api.getUserData(username, _selectedMode);
      } catch (_) {
        // API failure is not fatal if we have DB cache
      }

      int widgetId;

      if (_isFromWidgetTap) {
        // Configuring an existing widget that was tapped
        widgetId = widget.initialWidgetId!;
      } else {
        // In-app creation: save config globally, then request pin
        // The widget will pick up the config when added
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_global_username', username);
        await prefs.setString('pending_global_mode_key', modeKey);
        await prefs.setString('pending_global_mode_display', _selectedMode);
        await prefs.setString('pending_global_field_key', _selectedFieldKey);
        await prefs.setString(
          'pending_global_field_label',
          _selectedFieldLabel,
        );
        await prefs.setString('pending_global_time_range', _selectedTimeRange);
        await prefs.setInt(
          'pending_global_custom_days',
          _selectedTimeRange == '自定义' ? _customDays : 0,
        );

        if (!mounted) return;
        setState(() => _isSaving = false);

        // Request launcher to show "pin widget" dialog (Android 8.0+)
        try {
          await HomeWidget.requestPinWidget(
            name: 'OsustatsWidgetProvider',
            androidName: 'OsustatsWidgetProvider',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '已请求添加小组件，请在弹窗中确认\n请注意，在某些定制系统内可能无法生效，你可能需要自行添加小部件',
                ),
              ),
            );
          }
        } catch (_) {
          // requestPinWidget may fail on older Android or unsupported launchers
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已保存配置，请长按桌面手动添加小组件')));
          }
        }
        return;
      }

      // For existing widget (from widget tap): save config, render chart, update
      final config = WidgetConfig(
        widgetId: widgetId,
        username: username,
        modeKey: modeKey,
        modeDisplay: _selectedMode,
        fieldKey: _selectedFieldKey,
        fieldLabel: _selectedFieldLabel,
        timeRange: _selectedTimeRange,
        customDays: _selectedTimeRange == '自定义' ? _customDays : 0,
      );
      await _widgetService.saveWidgetConfig(config);

      // Render chart and update native widget (includes built-in cross-process delay)
      await _widgetService.refreshWidget(widgetId, config);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('小组件已配置 (玩家: $username)')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('配置桌面小组件')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isFromWidgetTap ? '配置桌面小组件' : '添加桌面小组件'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Hint banner
          Card(
            elevation: 0,
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isFromWidgetTap
                          ? '配置小组件显示的内容，保存后自动更新到桌面。'
                          : '配置完成后将自动请求添加到桌面，但在某些定制系统内可能无法生效',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Player selection
          _buildSelectorCard(
            icon: Icons.person,
            title: '选择玩家',
            subtitle: _userList.isEmpty ? '数据库中暂无玩家记录，请手动输入' : null,
            child: Column(
              children: [
                if (_userList.isEmpty)
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: '输入玩家用户名',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (val) =>
                        setState(() => _selectedUsername = val.trim()),
                  )
                else
                  _buildStyledDropdown<String>(
                    value: _selectedUsername,
                    items: _userList
                        .map(
                          (name) => DropdownMenuItem(
                            value: name,
                            child: Text(name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedUsername = value;
                        _usernameController.text = value ?? '';
                      });
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Mode selection
          _buildSelectorCard(
            icon: Icons.videogame_asset,
            title: '游戏模式',
            child: _buildStyledDropdown<String>(
              value: _selectedMode,
              items: const [
                DropdownMenuItem(value: 'osu', child: Text('osu!')),
                DropdownMenuItem(value: 'taiko', child: Text('osu!taiko')),
                DropdownMenuItem(value: 'fruits', child: Text('osu!catch')),
                DropdownMenuItem(value: 'mania', child: Text('osu!mania')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _selectedMode = value);
              },
            ),
          ),
          const SizedBox(height: 8),

          // Stat selection
          _buildSelectorCard(
            icon: Icons.bar_chart,
            title: '显示数据',
            child: _buildStyledDropdown<String>(
              value: _selectedFieldKey,
              items: _statOptions.map((opt) {
                return DropdownMenuItem(
                  value: opt['fieldKey'] as String,
                  child: Text(opt['label'] as String),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  final selected = _statOptions.firstWhere(
                    (o) => o['fieldKey'] == value,
                  );
                  setState(() {
                    _selectedFieldKey = value;
                    _selectedFieldLabel = selected['label'] as String;
                  });
                }
              },
            ),
          ),
          const SizedBox(height: 8),

          // Time range selection
          _buildSelectorCard(
            icon: Icons.date_range,
            title: '数据区间',
            child: Column(
              children: [
                _buildStyledDropdown<String>(
                  value: _selectedTimeRange,
                  items: _timeRanges
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedTimeRange = value);
                    }
                  },
                ),
                if (_selectedTimeRange == '自定义') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customDaysController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '输入天数',
                      prefixIcon: const Icon(Icons.edit_calendar),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixText: '天',
                    ),
                    onChanged: (val) {
                      setState(() {
                        _customDays = int.tryParse(val) ?? 0;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _onSave,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _isFromWidgetTap ? Icons.save : Icons.add_to_home_screen,
                    ),
              label: Text(
                _isSaving
                    ? '保存中...'
                    : _isFromWidgetTap
                    ? '保存配置'
                    : '保存并添加到桌面',
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSelectorCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStyledDropdown<T>({
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
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
          onChanged: onChanged,
          items: items,
        ),
      ),
    );
  }
}
