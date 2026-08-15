import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../utils.dart';
import '../widgets/widget_chart_renderer.dart';
import 'osu_api_service.dart';
import 'database_service.dart';
import '../core/constants.dart';
import '../core/logger.dart';

class WidgetConfig {
  final int widgetId;
  final String username;
  final String modeKey;
  final String modeDisplay;
  final String fieldKey;
  final String fieldLabel;
  final String timeRange;
  final int customDays;

  WidgetConfig({
    required this.widgetId,
    required this.username,
    required this.modeKey,
    required this.modeDisplay,
    required this.fieldKey,
    required this.fieldLabel,
    required this.timeRange,
    this.customDays = 0,
  });
}

class WidgetDataService {
  static final WidgetDataService _instance = WidgetDataService._();
  factory WidgetDataService() => _instance;
  WidgetDataService._();

  static const _cacheMinIntervalMinutes = 15;

  static const _providerNames = [
    'OsustatsWidgetProvider',
    'OsustatsWidgetProvider4x2',
  ];

  Future<void> updateAllWidgets() async {
    await Future.delayed(const Duration(milliseconds: 500));
    for (final name in _providerNames) {
      try {
        await HomeWidget.updateWidget(
          name: name,
          androidName: name,
          iOSName: null,
          qualifiedAndroidName: null,
        );
      } catch (e, stackTrace) {
        appLogger.e('Failed to update widget $name', error: e, stackTrace: stackTrace);
      }
    }
  }
  static const _chartStaleMinutes = 30;

  static const _modeDisplayMap = {
    AppConstants.colOsuJson: 'osu',
    AppConstants.colTaikoJson: 'taiko',
    AppConstants.colFruitsJson: 'fruits',
    AppConstants.colManiaJson: 'mania',
  };

  static const _modeDisplayToKey = {
    'osu': AppConstants.colOsuJson,
    'taiko': AppConstants.colTaikoJson,
    'fruits': AppConstants.colFruitsJson,
    'mania': AppConstants.colManiaJson,
  };

  String modeKeyToDisplay(String modeKey) => _modeDisplayMap[modeKey] ?? 'osu';
  String modeDisplayToKey(String modeDisplay) =>
      _modeDisplayToKey[modeDisplay] ?? AppConstants.colOsuJson;

  Future<List<int>> getActiveWidgetIds() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(AppConstants.keyActiveWidgetIds);
    if (str == null || str.isEmpty) return [];
    try {
      final list = (jsonDecode(str) as List).cast<String>();
      return list.map((s) => int.tryParse(s)).whereType<int>().toList();
    } catch (e, stackTrace) {
      appLogger.e('Failed to parse active widget ids', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  Future<void> _addActiveWidgetId(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getActiveWidgetIds();
    if (!ids.contains(widgetId)) {
      ids.add(widgetId);
      await prefs.setString(
        AppConstants.keyActiveWidgetIds,
        jsonEncode(ids.map((e) => e.toString()).toList()),
      );
    }
  }

  Future<void> _removeActiveWidgetId(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getActiveWidgetIds();
    ids.remove(widgetId);
    await prefs.setString(
      AppConstants.keyActiveWidgetIds,
      jsonEncode(ids.map((e) => e.toString()).toList()),
    );
  }

  Future<void> saveWidgetConfig(WidgetConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('widget_${config.widgetId}_username', config.username);
    await prefs.setString('widget_${config.widgetId}_mode_key', config.modeKey);
    await prefs.setString('widget_${config.widgetId}_mode_display', config.modeDisplay);
    await prefs.setString('widget_${config.widgetId}_field_key', config.fieldKey);
    await prefs.setString('widget_${config.widgetId}_field_label', config.fieldLabel);
    await prefs.setString('widget_${config.widgetId}_time_range', config.timeRange);
    await prefs.setInt('widget_${config.widgetId}_custom_days', config.customDays);

    await _addActiveWidgetId(config.widgetId);
  }

  Future<WidgetConfig?> loadWidgetConfig(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('widget_${widgetId}_username');
    if (username == null) return null;

    return WidgetConfig(
      widgetId: widgetId,
      username: username,
      modeKey: prefs.getString('widget_${widgetId}_mode_key') ?? AppConstants.colOsuJson,
      modeDisplay: prefs.getString('widget_${widgetId}_mode_display') ?? 'osu',
      fieldKey: prefs.getString('widget_${widgetId}_field_key') ?? 'pp',
      fieldLabel: prefs.getString('widget_${widgetId}_field_label') ?? 'pp',
      timeRange: prefs.getString('widget_${widgetId}_time_range') ?? AppConstants.rangeAll,
      customDays: prefs.getInt('widget_${widgetId}_custom_days') ?? 0,
    );
  }

  Future<bool> _shouldFetchFromApi(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetch = prefs.getInt('widget_${widgetId}_last_api_fetch') ?? 0;
    if (lastFetch == 0) return true;
    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastFetch);
    return DateTime.now().difference(lastTime).inMinutes >= _cacheMinIntervalMinutes;
  }

  Future<Map<String, dynamic>?> fetchWidgetData(
    WidgetConfig config, {
    /// Per-refresh-pass API result cache keyed by 'username|mode' so multiple
    /// widgets configured for the same player/mode share a single request
    /// instead of hitting the API once per widget.
    Map<String, Map<String, dynamic>>? apiCache,
  }) async {
    final db = DatabaseService();
    final api = OsuApiService();
    final prefs = await SharedPreferences.getInstance();

    final modeDisplay = modeKeyToDisplay(config.modeKey);
    final cacheKey = '${config.username}|$modeDisplay';

    Map<String, dynamic>? apiData;
    if (apiCache != null && apiCache.containsKey(cacheKey)) {
      apiData = apiCache[cacheKey];
    } else if (await _shouldFetchFromApi(config.widgetId)) {
      try {
        apiData = await api.getUserData(config.username, modeDisplay);
        if (apiCache != null) apiCache[cacheKey] = apiData;
      } catch (e, stackTrace) {
        appLogger.e('Failed to fetch API data for widget, falling back to cache', error: e, stackTrace: stackTrace);
      }
    }

    if (apiData != null) {
      final userId = apiData['id'] as int?;
      final stats = apiData['statistics'] as Map<String, dynamic>?;

      if (userId != null && stats != null && stats['play_count'] != null) {
        final currentValue = stats[config.fieldKey];

        await prefs.setInt('widget_${config.widgetId}_last_api_fetch', DateTime.now().millisecondsSinceEpoch);
        await prefs.setString('widget_${config.widgetId}_raw_data', jsonEncode(apiData));

        if (await db.hasModeChangedFromLatest(userId: userId, modeKey: config.modeKey, newData: apiData)) {
          final latest = await db.getLatestRecord(userId);
          await db.saveUserData(
            userId: userId,
            username: config.username,
            countryCode: apiData['country_code'] as String?,
            beatmapPlaycountsCount: apiData['beatmap_playcounts_count'] as int?,
            followerCount: apiData['follower_count'] as int?,
            userAchievements: apiData['user_achievements'] as List?,
            osuJson: config.modeKey == AppConstants.colOsuJson ? jsonEncode(apiData) : latest?[AppConstants.colOsuJson] as String?,
            taikoJson: config.modeKey == AppConstants.colTaikoJson ? jsonEncode(apiData) : latest?[AppConstants.colTaikoJson] as String?,
            fruitsJson: config.modeKey == AppConstants.colFruitsJson ? jsonEncode(apiData) : latest?[AppConstants.colFruitsJson] as String?,
            maniaJson: config.modeKey == AppConstants.colManiaJson ? jsonEncode(apiData) : latest?[AppConstants.colManiaJson] as String?,
          );
          await db.cleanupUserRecords(userId);
        }

        final history = await db.getRecordsForUser(userId);
        final dataPoints = await _extractDataPoints(history, config.modeKey, config.fieldKey, config);
        final formattedValue = _formatStatValue(currentValue, config.fieldKey);

        return {
          'dataPoints': dataPoints,
          'currentValue': currentValue,
          'currentValueFormatted': formattedValue,
          'username': config.username,
        };
      }
    }

    // Cache fallback: newest known snapshot for this username (index-backed
    // single-row lookup instead of scanning the whole table).
    final userRecord = await db.getLatestRecordByUsername(config.username);
    final userId = userRecord?[AppConstants.colUserId] as int?;

    if (userId != null) {
      final history = await db.getRecordsForUser(userId);
      final dataPoints = await _extractDataPoints(history, config.modeKey, config.fieldKey, config);

      dynamic currentValue;
      final latestJson = userRecord?[config.modeKey] as String?;
      if (latestJson != null && latestJson.isNotEmpty) {
        try {
          final data = jsonDecode(latestJson) as Map<String, dynamic>;
          final stats = data['statistics'] as Map<String, dynamic>? ?? {};
          currentValue = stats[config.fieldKey];
        } catch (e, stackTrace) {
          appLogger.e('Failed to parse cached user data', error: e, stackTrace: stackTrace);
        }
      }

      final formattedValue = _formatStatValue(currentValue, config.fieldKey);

      return {
        'dataPoints': dataPoints,
        'currentValue': currentValue,
        'currentValueFormatted': formattedValue,
        'username': config.username,
      };
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _extractDataPoints(
    List<Map<String, dynamic>> history,
    String modeKey,
    String fieldKey,
    WidgetConfig config,
  ) async {
    int? startTimeMs;
    final now = DateTime.now();

    if (config.timeRange == AppConstants.range1Day) {
      startTimeMs = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    } else if (config.timeRange == AppConstants.range3Days) {
      startTimeMs = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    } else if (config.timeRange == AppConstants.range7Days) {
      startTimeMs = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    } else if (config.timeRange == AppConstants.range1Month) {
      startTimeMs = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    } else if (config.timeRange == AppConstants.rangeCustom && config.customDays > 0) {
      startTimeMs = now.subtract(Duration(days: config.customDays)).millisecondsSinceEpoch;
    }

    // History is newest-first; reverse to chronological order, then decode
    // off the calling isolate via the shared util.
    return compute(computeDataPoints, {
      'history': history.reversed.toList(),
      'modeKey': modeKey,
      'fieldKey': fieldKey,
      'startTimeMs': startTimeMs,
    });
  }

  String _formatStatValue(dynamic value, String fieldKey) {
    if (value == null) return '-';
    if (fieldKey == 'accuracy') {
      return '${((value as num).toDouble() * 100).toStringAsFixed(2)}%';
    } else if (fieldKey == 'play_time') {
      return formatDuration((value as num).toInt());
    } else if (fieldKey == 'global_rank' || fieldKey == 'country_rank') {
      return '#${formatNumCompact(value)}';
    } else {
      return formatNumCompact(value);
    }
  }

  Future<bool> isChartStale(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastRender = prefs.getInt('widget_${widgetId}_last_chart_render') ?? 0;
    if (lastRender == 0) return true;
    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastRender);
    return DateTime.now().difference(lastTime).inMinutes >= _chartStaleMinutes;
  }

  Future<void> refreshAllWidgetCharts() async {
    final activeIds = await getActiveWidgetIds();
    // One API result per (username, mode) for the whole pass.
    final apiCache = <String, Map<String, dynamic>>{};
    for (final widgetId in activeIds) {
      try {
        final config = await loadWidgetConfig(widgetId);
        if (config == null) continue;
        if (!await isChartStale(widgetId)) continue;
        await refreshWidget(widgetId, config, apiCache: apiCache);
      } catch (e, stackTrace) {
        appLogger.e('Failed to refresh widget $widgetId', error: e, stackTrace: stackTrace);
      }
    }
  }

  Future<void> refreshWidget(
    int widgetId,
    WidgetConfig config, {
    Map<String, Map<String, dynamic>>? apiCache,
  }) async {
    final data = await fetchWidgetData(config, apiCache: apiCache);
    if (data == null) return;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('widget_${widgetId}_current_value', data['currentValueFormatted'] as String? ?? '-');
    await prefs.setString('widget_${widgetId}_username', config.username);
    await prefs.setString('widget_${widgetId}_field_label', config.fieldLabel);
    await prefs.setString('widget_${widgetId}_mode_display', config.modeDisplay);
    await prefs.setInt('widget_${widgetId}_last_api_fetch', DateTime.now().millisecondsSinceEpoch);

    try {
      final dataPoints = data['dataPoints'] as List<Map<String, dynamic>>? ?? [];

      final chartFile = await WidgetChartRenderer.render(
        widgetId: widgetId,
        dataPoints: dataPoints,
        widthDp: 230.0,
        heightDp: 80.0,
      );

      await prefs.setString('widget_${widgetId}_chart_path', chartFile.path);
      await prefs.setInt('widget_${widgetId}_last_chart_render', DateTime.now().millisecondsSinceEpoch);
    } catch (e, stackTrace) {
      appLogger.e('Chart rendering failed for widget $widgetId', error: e, stackTrace: stackTrace);
    }

    await updateAllWidgets();
  }

  Future<void> deleteWidgetConfig(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = [
      'widget_${widgetId}_username',
      'widget_${widgetId}_mode_key',
      'widget_${widgetId}_mode_display',
      'widget_${widgetId}_field_key',
      'widget_${widgetId}_field_label',
      'widget_${widgetId}_time_range',
      'widget_${widgetId}_custom_days',
      'widget_${widgetId}_last_api_fetch',
      'widget_${widgetId}_last_chart_render',
      'widget_${widgetId}_current_value',
      'widget_${widgetId}_raw_data',
      'widget_${widgetId}_chart_path',
    ];
    for (final key in keys) {
      await prefs.remove(key);
    }

    await _removeActiveWidgetId(widgetId);

    // Delete the rendered chart file so orphaned PNGs don't accumulate.
    final chartPath = prefs.getString('widget_${widgetId}_chart_path');
    if (chartPath != null && chartPath.isNotEmpty) {
      try {
        final file = File(chartPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e, stackTrace) {
        appLogger.e('Failed to delete chart file for widget $widgetId', error: e, stackTrace: stackTrace);
      }
    }
  }
}
