import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/osu_api_service.dart';
import '../core/secure_storage_service.dart';
import '../utils.dart';
import 'widget_config_page.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _savingCredentials = false;
  bool _savingUsername = false;
  bool _credentialsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    // Client credentials now live in secure storage (migrated from the legacy
    // plaintext SharedPreferences keys on first read).
    final creds = await SecureStorageService.getClientCredentials();
    final hasSavedCredentials = (creds.clientId?.isNotEmpty ?? false) ||
        (creds.clientSecret?.isNotEmpty ?? false);
    _clientIdController.text = creds.clientId ?? OsuApiService.defaultClientId;
    _clientSecretController.text = creds.clientSecret ?? OsuApiService.defaultClientSecret;
    final prefs = await SharedPreferences.getInstance();
    _usernameController.text = prefs.getString('query_username') ?? '';
    if (!mounted) return;
    setState(() {
      _credentialsExpanded = !hasSavedCredentials;
    });
  }

  Future<void> _saveCredentials() async {
    setState(() => _savingCredentials = true);
    try {
      // Sensitive OAuth credentials go to secure storage, not plaintext prefs.
      await SecureStorageService.saveClientCredentials(
        clientId: _clientIdController.text,
        clientSecret: _clientSecretController.text,
      );
      if (!mounted) return;
      setState(() {
        _credentialsExpanded = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('客户端 ID 和密钥已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingCredentials = false);
    }
  }

  Future<void> _saveUsername() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入用户名')),
      );
      return;
    }
    setState(() => _savingUsername = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('query_username', username);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('用户名 "$username" 已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingUsername = false);
    }
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final themeSettings = provider.themeSettings;
        return Scaffold(
          appBar: AppBar(
            title: const Text('设置'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            children: [
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: ExpansionTile(
                  initiallyExpanded: _credentialsExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() => _credentialsExpanded = expanded);
                  },
                  tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  leading: Icon(Icons.key, color: Theme.of(context).colorScheme.primary),
                  title: Text(
                    'API 凭据设置',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "请前往 osu! 官网获取自己的 OAuth 客户端 ID 和密钥，并在下方配置以便正常获取 API 数据。",
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final Uri url = Uri.parse('https://osu.ppy.sh/home/account/edit#oauth');
                              if (!await launchUrl(url)) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('无法打开链接')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('前往 osu! 官网获取'),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _clientIdController,
                            decoration: InputDecoration(
                              labelText: '客户端 ID',
                              hintText: '输入 OAuth 客户端 ID',
                              prefixIcon: const Icon(Icons.badge),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _clientSecretController,
                            decoration: InputDecoration(
                              labelText: '客户端密钥',
                              hintText: '输入 OAuth 客户端密钥',
                              prefixIcon: const Icon(Icons.lock),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            obscureText: true,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _savingCredentials ? null : _saveCredentials,
                              icon: _savingCredentials
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: Text(_savingCredentials ? '保存中...' : '保存凭据'),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Username Card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '默认查询用户',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "设置默认要查询的 osu! 用户名，可在主页直接加载。",
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'osu! 用户名',
                          hintText: '输入 osu! 用户名',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _savingUsername ? null : _saveUsername,
                          icon: _savingUsername
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: Text(_savingUsername ? '保存中...' : '保存用户名'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Appearance Settings Card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '界面外观设置',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Theme mode selection
                      Text(
                        '暗色模式',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AppThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: AppThemeMode.system,
                              icon: Icon(Icons.brightness_auto),
                              label: Text('系统'),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.light,
                              icon: Icon(Icons.light_mode),
                              label: Text('浅色'),
                            ),
                            ButtonSegment(
                              value: AppThemeMode.dark,
                              icon: Icon(Icons.dark_mode),
                              label: Text('深色'),
                            ),
                          ],
                          selected: {themeSettings.themeMode},
                          onSelectionChanged: (newSelection) {
                            provider.updateThemeSettings(themeMode: newSelection.first);
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Theme color selection
                      Text(
                        '主题颜色',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: predefinedColors.map((colorMap) {
                          final color = colorMap['color'] as Color;
                          final isSelected = !themeSettings.useDynamicColor &&
                              themeSettings.seedColor.toARGB32() == color.toARGB32();

                          return GestureDetector(
                            onTap: () {
                              provider.updateThemeSettings(
                                seedColor: color,
                                useDynamicColor: false,
                              );
                            },
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Dynamic color switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('使用动态取色'),
                        subtitle: const Text('开启后，将在支持的设备上（如 Android 12+）启用动态主题色。'),
                        value: themeSettings.useDynamicColor,
                        onChanged: (val) {
                          provider.updateThemeSettings(useDynamicColor: val);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Compare Target Settings Card
              Builder(
                builder: (context) {
                  final compareTarget = provider.compareTarget;
                  return Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.compare_arrows, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                '对比数据源设置',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "选择主页数据对比的基础。不同的选项会与不同时间点的数据进行比较。",
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<CompareTarget>(
                                value: compareTarget,
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
                                onChanged: (value) {
                                  if (value != null) provider.updateCompareTarget(value);
                                },
                                items: const [
                                  DropdownMenuItem(
                                    value: CompareTarget.lastQuery,
                                    child: Text('上次查询的数据'),
                                  ),
                                  DropdownMenuItem(
                                    value: CompareTarget.todayEarliest,
                                    child: Text('今日最早的数据'),
                                  ),
                                  DropdownMenuItem(
                                    value: CompareTarget.yesterdayLatest,
                                    child: Text('昨日最后的数据'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // Widget Management Card
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.widgets, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '桌面小组件',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "在桌面添加小组件以快速查看玩家数据趋势。支持 2x1 和 4x2 两种尺寸。",
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const WidgetConfigPage()),
                            );
                          },
                          icon: const Icon(Icons.add_to_home_screen),
                          label: const Text('添加新组件'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
