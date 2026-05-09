import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osu_api_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _savingCredentials = false;
  bool _savingUsername = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _clientIdController.text =
        prefs.getString('client_id') ?? OsuApiService.defaultClientId;
    _clientSecretController.text =
        prefs.getString('client_secret') ?? OsuApiService.defaultClientSecret;
    _usernameController.text = prefs.getString('query_username') ?? '';
    setState(() {});
  }

  Future<void> _saveCredentials() async {
    setState(() => _savingCredentials = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('client_id', _clientIdController.text);
      await prefs.setString('client_secret', _clientSecretController.text);
      if (!mounted) return;
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
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text("请前往 osu! 官网获取自己的 OAuth 客户端 ID 和密钥"),
          const SizedBox(height: 16),
          TextField(
            controller: _clientIdController,
            decoration: const InputDecoration(
              labelText: '客户端 ID',
              hintText: '输入 OAuth 客户端 ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _clientSecretController,
            decoration: const InputDecoration(
              labelText: '客户端密钥',
              hintText: '输入 OAuth 客户端密钥',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _savingCredentials ? null : _saveCredentials,
              icon: _savingCredentials
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_savingCredentials ? '保存中...' : '保存凭据'),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 32),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'osu! 用户名',
              hintText: '输入 osu! 用户名',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _savingUsername ? null : _saveUsername,
              icon: _savingUsername
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_savingUsername ? '保存中...' : '保存用户名'),
            ),
          ),
        ],
      ),
    );
  }
}
