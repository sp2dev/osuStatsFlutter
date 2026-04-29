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
            user_id INTEGER PRIMARY KEY,
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

  Future<void> saveUserData({
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
    await db.insert(
      'user_cache',
      {
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return db.query('user_cache', orderBy: 'updated_at DESC');
  }

  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final db = await database;
    final results = await db.query(
      'user_cache',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<bool> hasDataChanged({
    required int userId,
    String? osuJson,
    String? taikoJson,
    String? fruitsJson,
    String? maniaJson,
  }) async {
    final existing = await getUserById(userId);
    if (existing == null) return true;
    return (existing['osu_json'] as String?) != osuJson ||
        (existing['taiko_json'] as String?) != taikoJson ||
        (existing['fruits_json'] as String?) != fruitsJson ||
        (existing['mania_json'] as String?) != maniaJson;
  }

  Future<void> deleteUser(int userId) async {
    final db = await database;
    await db.delete('user_cache', where: 'user_id = ?', whereArgs: [userId]);
  }
}
