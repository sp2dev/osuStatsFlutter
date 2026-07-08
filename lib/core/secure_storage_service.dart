import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const String _keyAccessToken = 'access_token';
  static const String _keyTokenExpiresAt = 'token_expires_at';
  
  static Future<void> saveToken(String token, DateTime expiresAt) async {
    await _storage.write(key: _keyAccessToken, value: token);
    await _storage.write(key: _keyTokenExpiresAt, value: expiresAt.toIso8601String());
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _keyAccessToken);
  }

  static Future<DateTime?> getTokenExpiry() async {
    final expiresAtStr = await _storage.read(key: _keyTokenExpiresAt);
    if (expiresAtStr != null) {
      return DateTime.tryParse(expiresAtStr);
    }
    return null;
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyTokenExpiresAt);
  }
}
