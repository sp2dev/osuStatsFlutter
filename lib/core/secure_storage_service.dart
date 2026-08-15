import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

/// Central storage for anything sensitive (OAuth tokens, client credentials).
///
/// Access tokens and client credentials live in platform secure storage
/// (Keychain / Keystore-backed). Client credentials are migrated from the
/// legacy plaintext SharedPreferences keys on first read.
class SecureStorageService {
  SecureStorageService._();

  static const _storage = FlutterSecureStorage();

  // --- Access token ---

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

  // --- Client credentials (OAuth client_id / client_secret) ---

  static const String _keyClientId = 'client_id';
  static const String _keyClientSecret = 'client_secret';

  static Future<void> saveClientCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    await _storage.write(key: _keyClientId, value: clientId);
    await _storage.write(key: _keyClientSecret, value: clientSecret);
  }

  /// Reads client credentials, transparently migrating from the legacy
  /// plaintext SharedPreferences keys on first access.
  static Future<({String? clientId, String? clientSecret})> getClientCredentials() async {
    final storedId = await _storage.read(key: _keyClientId);
    final storedSecret = await _storage.read(key: _keyClientSecret);
    if (storedId != null || storedSecret != null) {
      return (clientId: storedId, clientSecret: storedSecret);
    }

    // Legacy migration: values were previously kept in SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final legacyId = prefs.getString(AppConstants.keyClientId);
    final legacySecret = prefs.getString(AppConstants.keyClientSecret);
    if (legacyId != null || legacySecret != null) {
      await saveClientCredentials(
        clientId: legacyId ?? '',
        clientSecret: legacySecret ?? '',
      );
      await prefs.remove(AppConstants.keyClientId);
      await prefs.remove(AppConstants.keyClientSecret);
      return (clientId: legacyId, clientSecret: legacySecret);
    }
    return (clientId: null, clientSecret: null);
  }

  static Future<bool> hasClientCredentials() async {
    final creds = await getClientCredentials();
    return (creds.clientId?.isNotEmpty ?? false) ||
        (creds.clientSecret?.isNotEmpty ?? false);
  }

  static Future<void> clearClientCredentials() async {
    await _storage.delete(key: _keyClientId);
    await _storage.delete(key: _keyClientSecret);
  }
}
