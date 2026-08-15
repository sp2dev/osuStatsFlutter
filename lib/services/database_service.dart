import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../core/constants.dart';
import '../core/logger.dart';

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
    final path = join(dbPath, AppConstants.dbName);
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ${AppConstants.tableUserCache} (
            ${AppConstants.colId} INTEGER PRIMARY KEY AUTOINCREMENT,
            ${AppConstants.colUserId} INTEGER NOT NULL,
            ${AppConstants.colUsername} TEXT NOT NULL,
            ${AppConstants.colCountryCode} TEXT,
            ${AppConstants.colBeatmapPlaycountsCount} INTEGER,
            ${AppConstants.colFollowerCount} INTEGER,
            ${AppConstants.colUserAchievements} TEXT,
            ${AppConstants.colOsuJson} TEXT,
            ${AppConstants.colTaikoJson} TEXT,
            ${AppConstants.colFruitsJson} TEXT,
            ${AppConstants.colManiaJson} TEXT,
            ${AppConstants.colUpdatedAt} INTEGER NOT NULL
          )
        ''');
        await _createIndexes(db);
        appLogger.i('Database initialized and tables created.');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createIndexes(db);
          appLogger.i('Database upgraded to v2 (history lookup indexes).');
        }
      },
    );
  }

  /// Indexes backing the hot query paths (per-user history lookups).
  /// Kept in a helper so onCreate/onUpgrade stay in sync.
  static Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_cache_user_time '
      'ON ${AppConstants.tableUserCache} (${AppConstants.colUserId}, ${AppConstants.colUpdatedAt} DESC)',
    );
  }

  Future<Map<String, dynamic>?> getLatestRecord(int userId) async {
    try {
      final db = await database;
      final results = await db.query(
        AppConstants.tableUserCache,
        where: '${AppConstants.colUserId} = ?',
        whereArgs: [userId],
        orderBy: '${AppConstants.colUpdatedAt} DESC',
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e, stackTrace) {
      appLogger.e('Error getting latest record', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPreviousRecord(int userId, int currentUpdatedAt) async {
    try {
      final db = await database;
      final results = await db.query(
        AppConstants.tableUserCache,
        where: '${AppConstants.colUserId} = ? AND ${AppConstants.colUpdatedAt} < ?',
        whereArgs: [userId, currentUpdatedAt],
        orderBy: '${AppConstants.colUpdatedAt} DESC',
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e, stackTrace) {
      appLogger.e('Error getting previous record', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getRecordsForUser(int userId) async {
    try {
      final db = await database;
      return db.query(
        AppConstants.tableUserCache,
        where: '${AppConstants.colUserId} = ?',
        whereArgs: [userId],
        orderBy: '${AppConstants.colUpdatedAt} DESC',
      );
    } catch (e, stackTrace) {
      appLogger.e('Error getting records for user', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  static String _stableFingerprint(Map<String, dynamic>? data) {
    if (data == null) return '';
    final stats = data['statistics'] as Map<String, dynamic>? ?? {};
    final level = stats['level'] as Map<String, dynamic>? ?? {};
    return jsonEncode({
      'beatmap_playcounts_count': data['beatmap_playcounts_count'],
      'follower_count': data['follower_count'],
      // Achievements only change by being granted, so their count is a
      // sufficient (and much cheaper) change signal than the full list.
      'achievements_count': (data['user_achievements'] as List?)?.length,
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

  Future<bool> hasModeChangedFromLatest({
    required int userId,
    required String modeKey,
    required Map<String, dynamic> newData,
  }) async {
    final latest = await getLatestRecord(userId);
    if (latest == null) return true;
    final storedJson = latest[modeKey] as String?;
    return _stableFingerprint(newData) != _fpFromStored(storedJson);
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
    return _stableFingerprint(osuData) != _fpFromStored(latest[AppConstants.colOsuJson] as String?) ||
        _stableFingerprint(taikoData) != _fpFromStored(latest[AppConstants.colTaikoJson] as String?) ||
        _stableFingerprint(fruitsData) != _fpFromStored(latest[AppConstants.colFruitsJson] as String?) ||
        _stableFingerprint(maniaData) != _fpFromStored(latest[AppConstants.colManiaJson] as String?);
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
    try {
      final db = await database;
      return db.insert(AppConstants.tableUserCache, {
        AppConstants.colUserId: userId,
        AppConstants.colUsername: username,
        AppConstants.colCountryCode: countryCode,
        AppConstants.colBeatmapPlaycountsCount: beatmapPlaycountsCount,
        AppConstants.colFollowerCount: followerCount,
        AppConstants.colUserAchievements:
            userAchievements != null ? jsonEncode(userAchievements) : null,
        AppConstants.colOsuJson: osuJson,
        AppConstants.colTaikoJson: taikoJson,
        AppConstants.colFruitsJson: fruitsJson,
        AppConstants.colManiaJson: maniaJson,
        AppConstants.colUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e, stackTrace) {
      appLogger.e('Error saving user data', error: e, stackTrace: stackTrace);
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final db = await database;
      return db.query(AppConstants.tableUserCache, orderBy: '${AppConstants.colUpdatedAt} DESC');
    } catch (e, stackTrace) {
      appLogger.e('Error getting all users', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Lightweight distinct-username list (no full-table payload).
  /// Used by screens that only need a name picker.
  Future<List<String>> getDistinctUsernames() async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT DISTINCT ${AppConstants.colUsername} FROM ${AppConstants.tableUserCache} '
        'ORDER BY ${AppConstants.colUsername} COLLATE NOCASE',
      );
      return rows.map((r) => r[AppConstants.colUsername] as String).toList();
    } catch (e, stackTrace) {
      appLogger.e('Error getting distinct usernames', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Newest snapshot row for a username (index-backed single-row lookup).
  Future<Map<String, dynamic>?> getLatestRecordByUsername(String username) async {
    try {
      final db = await database;
      final results = await db.query(
        AppConstants.tableUserCache,
        where: '${AppConstants.colUsername} = ?',
        whereArgs: [username],
        orderBy: '${AppConstants.colUpdatedAt} DESC',
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e, stackTrace) {
      appLogger.e('Error getting latest record by username', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> deleteRecord(int id) async {
    try {
      final db = await database;
      await db.delete(AppConstants.tableUserCache, where: '${AppConstants.colId} = ?', whereArgs: [id]);
    } catch (e, stackTrace) {
      appLogger.e('Error deleting record', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> deleteAllRecordsForUser(int userId) async {
    try {
      final db = await database;
      await db.delete(AppConstants.tableUserCache, where: '${AppConstants.colUserId} = ?', whereArgs: [userId]);
    } catch (e, stackTrace) {
      appLogger.e('Error deleting all records for user', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> cleanupUserRecords(int userId) async {
    try {
      final db = await database;
      final records = await getRecordsForUser(userId);
      
      Map<String, List<Map<String, dynamic>>> recordsByDay = {};
      for (var record in records) {
        final date = DateTime.fromMillisecondsSinceEpoch(record[AppConstants.colUpdatedAt] as int);
        final dayKey = '${date.year}-${date.month}-${date.day}';
        recordsByDay.putIfAbsent(dayKey, () => []).add(record);
      }
      
      List<int> idsToDelete = [];
      
      for (var dailyRecords in recordsByDay.values) {
        if (dailyRecords.length > 2) {
          for (int i = 1; i < dailyRecords.length - 1; i++) {
            idsToDelete.add(dailyRecords[i][AppConstants.colId] as int);
          }
        }
      }
      
      if (idsToDelete.isNotEmpty) {
        Batch batch = db.batch();
        for (int id in idsToDelete) {
          batch.delete(AppConstants.tableUserCache, where: '${AppConstants.colId} = ?', whereArgs: [id]);
        }
        await batch.commit();
        appLogger.i('Cleaned up ${idsToDelete.length} records for user $userId');
      }
    } catch (e, stackTrace) {
      appLogger.e('Error cleaning up user records', error: e, stackTrace: stackTrace);
    }
  }
}
