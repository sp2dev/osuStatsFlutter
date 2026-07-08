import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/secure_storage_service.dart';
import '../core/constants.dart';
import '../core/logger.dart';

class OsuApiService {
  static const String _tokenUrl = 'https://osu.ppy.sh/oauth/token';
  static const String _apiBase = 'https://osu.ppy.sh/api/v2';

  static const String defaultClientId = '';
  static const String defaultClientSecret = '';

  late final Dio _dio;

  OsuApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: _apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Don't attach token if it's the token endpoint
        if (options.path == _tokenUrl) {
          return handler.next(options);
        }

        final token = await _getToken();
        options.headers['Authorization'] = 'Bearer $token';
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401 && e.requestOptions.path != _tokenUrl) {
          appLogger.w('Token expired, attempting to refresh...');
          try {
            await SecureStorageService.clearToken();
            final newToken = await _getToken();
            
            // Retry request
            final opts = e.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newToken';
            
            final cloneReq = await _dio.fetch(opts);
            return handler.resolve(cloneReq);
          } catch (retryError) {
            appLogger.e('Failed to refresh token and retry', error: retryError);
            return handler.next(e);
          }
        }
        return handler.next(e);
      },
    ));
    
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: false,
      responseHeader: false,
      responseBody: false,
      error: true,
      logPrint: (obj) => appLogger.d(obj.toString()),
    ));
  }

  String get _platformHint {
    if (kIsWeb) {
      return '当前运行在 Web 平台，浏览器的 CORS 策略会阻止跨域请求。\n'
          '请使用 flutter run -d windows 在桌面端运行，'
          '或 flutter run -d android 在安卓设备上运行。';
    }
    return '请检查网络连接，确认可以访问 osu.ppy.sh。';
  }

  Future<String> _getToken() async {
    final savedToken = await SecureStorageService.getToken();
    final expiresAt = await SecureStorageService.getTokenExpiry();

    if (savedToken != null && expiresAt != null) {
      if (DateTime.now().isBefore(expiresAt)) {
        return savedToken;
      }
    }

    return await _tokenWithClientCredentials();
  }

  Future<String> _tokenWithClientCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString(AppConstants.keyClientId) ?? defaultClientId;
    final clientSecret = prefs.getString(AppConstants.keyClientSecret) ?? defaultClientSecret;

    try {
      final response = await _dio.post(
        _tokenUrl,
        data: {
          'client_id': clientId,
          'client_secret': clientSecret,
          'grant_type': 'client_credentials',
          'scope': 'public',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final accessToken = data['access_token'] as String;
        final expiresIn = data['expires_in'] as int? ?? 86400;
        final expiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));

        await SecureStorageService.saveToken(accessToken, expiresAt);
        return accessToken;
      }
      throw Exception('client_credentials 失败: ${response.statusCode}');
    } on DioException catch (e) {
      appLogger.e('Token fetch failed', error: e);
      throw Exception('网络请求失败\n$_platformHint\n\n原始错误: ${e.message}');
    }
  }

  /// 获取指定用户的指定模式数据
  Future<Map<String, dynamic>> getUserData(String username, String mode) async {
    try {
      final response = await _dio.get('/users/@$username/$mode');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      appLogger.e('Failed to fetch user data for $username ($mode)', error: e);
      if (e.response?.statusCode == 404) {
        throw Exception('未找到玩家 "$username" 的 $mode 模式数据，请检查用户名是否正确');
      }
      throw Exception('获取 $username 的 $mode 数据失败: ${e.message}\n$_platformHint');
    }
  }
}
