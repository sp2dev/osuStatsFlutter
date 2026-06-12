import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._();
  factory DatabaseService() => _instance;
  DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'osu_stats.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE user_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            username TEXT NOT NULL,
            country_code TEXT,
            beatmap_playcounts_count INTEGER,
            follower_count INTEGER,
            user_achievements TEXT,
            osu_json TEXT,
            taiko_json TEXT,
            fruits_json TEXT,
            mania_json TEXT,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<Map<String, dynamic>?> getLatestRecord(int userId) async {
    final db = await database;
    final results = await db.query(
      'user_cache',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getPreviousRecord(int userId, int currentUpdatedAt) async {
    final db = await database;
    final results = await db.query(
      'user_cache',
      where: 'user_id = ? AND updated_at < ?',
      whereArgs: [userId, currentUpdatedAt],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  static String _stableFingerprint(Map<String, dynamic>? data) {
    if (data == null) return '';
    final stats = data['statistics'] as Map<String, dynamic>? ?? {};
    final level = stats['level'] as Map<String, dynamic>? ?? {};
    return jsonEncode({
      'beatmap_playcounts_count': data['beatmap_playcounts_count'],
      'follower_count': data['follower_count'],
      'user_achievements': data['user_achievements'],
      'stats': {
        'global_rank': stats['global_rank'],
        'country_rank': stats['country_rank'],
        'accuracy': stats['accuracy'],
        'level_current': level['current'],
        'level_progress': level['progress'],
        'play_count': stats['play_count'],
        'play_time': stats['play_time'],
        'pp': stats['pp'],
        'ranked_score': stats['ranked_score'],
        'total_hits': stats['total_hits'],
        'total_score': stats['total_score'],
      },
    });
  }

  String? _fpFromStored(String? jsonStr) {
    if (jsonStr == null) return null;
    try {
      return _stableFingerprint(jsonDecode(jsonStr) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasChangedFromLatest({
    required int userId,
    Map<String, dynamic>? osuData,
    Map<String, dynamic>? taikoData,
    Map<String, dynamic>? fruitsData,
    Map<String, dynamic>? maniaData,
  }) async {
    final latest = await getLatestRecord(userId);
    if (latest == null) return true;
    return _stableFingerprint(osuData) != _fpFromStored(latest['osu_json'] as String?) ||
        _stableFingerprint(taikoData) != _fpFromStored(latest['taiko_json'] as String?) ||
        _stableFingerprint(fruitsData) != _fpFromStored(latest['fruits_json'] as String?) ||
        _stableFingerprint(maniaData) != _fpFromStored(latest['mania_json'] as String?);
  }

  Future<int> saveUserData({
    required int userId,
    required String username,
    String? countryCode,
    int? beatmapPlaycountsCount,
    int? followerCount,
    List? userAchievements,
    String? osuJson,
    String? taikoJson,
    String? fruitsJson,
    String? maniaJson,
  }) async {
    final db = await database;
    return db.insert('user_cache', {
      'user_id': userId,
      'username': username,
      'country_code': countryCode,
      'beatmap_playcounts_count': beatmapPlaycountsCount,
      'follower_count': followerCount,
      'user_achievements':
          userAchievements != null ? jsonEncode(userAchievements) : null,
      'osu_json': osuJson,
      'taiko_json': taikoJson,
      'fruits_json': fruitsJson,
      'mania_json': maniaJson,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return db.query('user_cache', orderBy: 'updated_at DESC');
  }

  Future<void> deleteRecord(int id) async {
    final db = await database;
    await db.delete('user_cache', where: 'id = ?', whereArgs: [id]);
  }
}
