import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OsuApiService {
  static const String _tokenUrl = 'https://osu.ppy.sh/oauth/token';
  static const String _apiBase = 'https://osu.ppy.sh/api/v2';

  static const String defaultClientId = '';
  static const String defaultClientSecret =
      '';

  String? _accessToken;

  String get _platformHint {
    if (kIsWeb) {
      return '当前运行在 Web 平台，浏览器的 CORS 策略会阻止跨域请求。'
          '请使用 flutter run -d windows 在桌面端运行，'
          '或 flutter run -d android 在安卓设备上运行。';
    }
    return '请检查网络连接，确认可以访问 osu.ppy.sh。';
  }

  final http.Client _client = http.Client();

  Future<http.Response> _post(String url, Map<String, String> body) async {
    try {
      return await _client.post(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('网络请求失败\n$_platformHint\n\n原始错误: $e');
    }
  }

  Future<http.Response> _get(String url, String token) async {
    try {
      return await _client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw Exception('网络请求失败\n$_platformHint\n\n原始错误: $e');
    }
  }

  Future<String> _getToken() async {
    if (_accessToken != null) return _accessToken!;

    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('access_token');
    final expiresAt = prefs.getString('token_expires_at');

    if (savedToken != null && expiresAt != null) {
      final expiry = DateTime.tryParse(expiresAt);
      if (expiry != null && DateTime.now().isBefore(expiry)) {
        _accessToken = savedToken;
        return _accessToken!;
      }
    }

    return await _tokenWithClientCredentials();
  }

  Future<String> _tokenWithClientCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString('client_id') ?? defaultClientId;
    final clientSecret =
        prefs.getString('client_secret') ?? defaultClientSecret;

    final response = await _post(_tokenUrl, {
      'client_id': clientId,
      'client_secret': clientSecret,
      'grant_type': 'client_credentials',
      'scope': 'public',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return await _saveTokenData(data);
    }

    throw Exception('client_credentials 失败: ${response.statusCode}');
  }

  Future<String> _saveTokenData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = data['access_token'] as String;
    await prefs.setString('access_token', _accessToken!);

    final expiresIn = data['expires_in'] as int? ?? 86400;
    final expiresAt =
        DateTime.now().add(Duration(seconds: expiresIn - 60));
    await prefs.setString('token_expires_at', expiresAt.toIso8601String());

    return _accessToken!;
  }

  /// 获取指定用户的指定模式数据（使用 Get User 端点）
  Future<Map<String, dynamic>> getUserData(
      String username, String mode) async {
    final token = await _getToken();
    final response =
        await _get('$_apiBase/users/@$username/$mode', token);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    if (response.statusCode == 401) {
      _accessToken = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('token_expires_at');
      final newToken = await _getToken();
      final retryResponse =
          await _get('$_apiBase/users/$username/$mode', newToken);
      if (retryResponse.statusCode == 200) {
        return jsonDecode(retryResponse.body) as Map<String, dynamic>;
      }
    }

    throw Exception('获取 $username 的 $mode 数据失败: ${response.statusCode}');
  }
}
