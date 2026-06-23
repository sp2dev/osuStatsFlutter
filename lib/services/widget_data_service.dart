import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../utils.dart';
import '../widgets/widget_chart_renderer.dart';
import 'osu_api_service.dart';
import 'database_service.dart';

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

  /// Trigger native widget update for all provider classes.
  /// Includes a small delay before sending broadcast to allow SharedPreferences
  /// to flush to disk (cross-process visibility).
  Future<void> updateAllWidgets() async {
    // Allow pending SharedPreferences writes to commit (cross-process)
    await Future.delayed(const Duration(milliseconds: 500));
    for (final name in _providerNames) {
      try {
        await HomeWidget.updateWidget(
          name: name,
          androidName: name,
          iOSName: null,
          qualifiedAndroidName: null,
        );
      } catch (_) {}
    }
  }
  static const _chartStaleMinutes = 30;

  static const _modeDisplayMap = {
    'osu_json': 'osu',
    'taiko_json': 'taiko',
    'fruits_json': 'fruits',
    'mania_json': 'mania',
  };

  static const _modeDisplayToKey = {
    'osu': 'osu_json',
    'taiko': 'taiko_json',
    'fruits': 'fruits_json',
    'mania': 'mania_json',
  };

  String modeKeyToDisplay(String modeKey) => _modeDisplayMap[modeKey] ?? 'osu';
  String modeDisplayToKey(String modeDisplay) =>
      _modeDisplayToKey[modeDisplay] ?? 'osu_json';

  // --- Bug 1 fix: Use JSON string for active_widget_ids (cross-process safe) ---

  Future<List<int>> getActiveWidgetIds() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('active_widget_ids');
    if (str == null || str.isEmpty) return [];
    try {
      final list = (jsonDecode(str) as List).cast<String>();
      return list.map((s) => int.tryParse(s)).whereType<int>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _addActiveWidgetId(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getActiveWidgetIds();
    if (!ids.contains(widgetId)) {
      ids.add(widgetId);
      await prefs.setString(
        'active_widget_ids',
        jsonEncode(ids.map((e) => e.toString()).toList()),
      );
    }
  }

  Future<void> _removeActiveWidgetId(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = await getActiveWidgetIds();
    ids.remove(widgetId);
    await prefs.setString(
      'active_widget_ids',
      jsonEncode(ids.map((e) => e.toString()).toList()),
    );
  }

  Future<void> saveWidgetConfig(WidgetConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('widget_${config.widgetId}_username', config.username);
    await prefs.setString('widget_${config.widgetId}_mode_key', config.modeKey);
    await prefs.setString(
        'widget_${config.widgetId}_mode_display', config.modeDisplay);
    await prefs.setString('widget_${config.widgetId}_field_key', config.fieldKey);
    await prefs.setString(
        'widget_${config.widgetId}_field_label', config.fieldLabel);
    await prefs.setString(
        'widget_${config.widgetId}_time_range', config.timeRange);
    await prefs.setInt(
        'widget_${config.widgetId}_custom_days', config.customDays);

    // Track active widgets
    await _addActiveWidgetId(config.widgetId);
  }

  Future<WidgetConfig?> loadWidgetConfig(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('widget_${widgetId}_username');
    if (username == null) return null;

    return WidgetConfig(
      widgetId: widgetId,
      username: username,
      modeKey:
          prefs.getString('widget_${widgetId}_mode_key') ?? 'osu_json',
      modeDisplay:
          prefs.getString('widget_${widgetId}_mode_display') ?? 'osu',
      fieldKey:
          prefs.getString('widget_${widgetId}_field_key') ?? 'pp',
      fieldLabel:
          prefs.getString('widget_${widgetId}_field_label') ?? 'pp',
      timeRange:
          prefs.getString('widget_${widgetId}_time_range') ?? '全部',
      customDays:
          prefs.getInt('widget_${widgetId}_custom_days') ?? 0,
    );
  }

  Future<bool> _shouldFetchFromApi(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetch =
        prefs.getInt('widget_${widgetId}_last_api_fetch') ?? 0;
    if (lastFetch == 0) return true;
    final lastTime =
        DateTime.fromMillisecondsSinceEpoch(lastFetch);
    return DateTime.now()
        .difference(lastTime)
        .inMinutes >= _cacheMinIntervalMinutes;
  }

  /// Fetch data for a widget config, using cache when possible.
  /// Returns {dataPoints, currentValue, currentValueFormatted, username}.
  Future<Map<String, dynamic>?> fetchWidgetData(WidgetConfig config) async {
    final db = DatabaseService();
    final api = OsuApiService();
    final prefs = await SharedPreferences.getInstance();

    final modeDisplay = modeKeyToDisplay(config.modeKey);

    // Try to get a fresh API call if cache expired
    if (await _shouldFetchFromApi(config.widgetId)) {
      try {
        final apiData = await api.getUserData(config.username, modeDisplay);
        final userId = apiData['id'] as int?;
        if (userId != null) {
          final stats = apiData['statistics'] as Map<String, dynamic>? ?? {};
          final currentValue = stats[config.fieldKey];

          await prefs.setInt(
              'widget_${config.widgetId}_last_api_fetch',
              DateTime.now().millisecondsSinceEpoch);
          await prefs.setString(
              'widget_${config.widgetId}_raw_data', jsonEncode(apiData));

          // Build data points from history
          final history = await db.getRecordsForUser(userId);
          final dataPoints = _extractDataPoints(
              history, config.modeKey, config.fieldKey, config);

          final formattedValue = _formatStatValue(
              currentValue, config.fieldKey);

          return {
            'dataPoints': dataPoints,
            'currentValue': currentValue,
            'currentValueFormatted': formattedValue,
            'username': config.username,
          };
        }
      } catch (_) {
        // Fall back to DB cache
      }
    }

    // Use DB cache
    final users = await db.getAllUsers();
    Map<String, dynamic>? userRecord;
    int? userId;
    for (final u in users) {
      if (u['username'] == config.username) {
        userRecord = u;
        userId = u['user_id'] as int?;
        break;
      }
    }

    if (userId != null) {
      final history = await db.getRecordsForUser(userId);
      final dataPoints = _extractDataPoints(
          history, config.modeKey, config.fieldKey, config);

      // Get current value from latest record
      dynamic currentValue;
      final latestJson = userRecord?[config.modeKey] as String?;
      if (latestJson != null && latestJson.isNotEmpty) {
        try {
          final data = jsonDecode(latestJson) as Map<String, dynamic>;
          final stats = data['statistics'] as Map<String, dynamic>? ?? {};
          currentValue = stats[config.fieldKey];
        } catch (_) {}
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

  List<Map<String, dynamic>> _extractDataPoints(
    List<Map<String, dynamic>> history,
    String modeKey,
    String fieldKey,
    WidgetConfig config,
  ) {
    final dataPoints = <Map<String, dynamic>>[];
    int? startTimeMs;
    final now = DateTime.now();

    if (config.timeRange == '1天') {
      startTimeMs = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
    } else if (config.timeRange == '3天') {
      startTimeMs = now.subtract(const Duration(days: 3)).millisecondsSinceEpoch;
    } else if (config.timeRange == '7天') {
      startTimeMs = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    } else if (config.timeRange == '1个月') {
      startTimeMs = now.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    } else if (config.timeRange == '自定义' && config.customDays > 0) {
      startTimeMs =
          now.subtract(Duration(days: config.customDays)).millisecondsSinceEpoch;
    }

    for (final record in history.reversed) {
      final updatedAt = record['updated_at'] as int;
      if (startTimeMs != null && updatedAt < startTimeMs) {
        continue;
      }

      final jsonStr = record[modeKey] as String?;
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final stats = data['statistics'] as Map<String, dynamic>? ?? {};
          final value = stats[fieldKey];
          if (value != null) {
            num numValue = value as num;

            // Bug 4 fix: Apply data transforms consistent with chart_page.dart
            if (fieldKey == 'accuracy') {
              numValue = numValue * 100;
            } else if (fieldKey == 'play_time') {
              numValue = numValue / 3600.0;
            } else if (fieldKey == 'global_rank' || fieldKey == 'country_rank') {
              numValue = -numValue;
            }

            dataPoints.add({
              'time': DateTime.fromMillisecondsSinceEpoch(updatedAt),
              'value': numValue.toDouble(),
            });
          }
        } catch (_) {}
      }
    }

    return dataPoints;
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

  /// Check if chart bitmap is stale
  Future<bool> isChartStale(int widgetId) async {
    final prefs = await SharedPreferences.getInstance();
    final lastRender =
        prefs.getInt('widget_${widgetId}_last_chart_render') ?? 0;
    if (lastRender == 0) return true;
    final lastTime = DateTime.fromMillisecondsSinceEpoch(lastRender);
    return DateTime.now().difference(lastTime).inMinutes >= _chartStaleMinutes;
  }

  /// Refresh all widgets' chart bitmaps (called on app foreground)
  Future<void> refreshAllWidgetCharts() async {
    final activeIds = await getActiveWidgetIds();
    for (final widgetId in activeIds) {
      try {
        final config = await loadWidgetConfig(widgetId);
        if (config == null) continue;
        if (!await isChartStale(widgetId)) continue;
        await refreshWidget(widgetId, config);
      } catch (_) {
        // Silently skip failed widgets
      }
    }
  }

  /// Refresh a single widget (fetch data + render chart + update native widget)
  Future<void> refreshWidget(int widgetId, WidgetConfig config) async {
    final data = await fetchWidgetData(config);
    if (data == null) return;

    final prefs = await SharedPreferences.getInstance();

    // Save text values for native widget
    await prefs.setString('widget_${widgetId}_current_value',
        data['currentValueFormatted'] as String? ?? '-');
    await prefs.setString(
        'widget_${widgetId}_username', config.username);
    await prefs.setString(
        'widget_${widgetId}_field_label', config.fieldLabel);
    await prefs.setString(
        'widget_${widgetId}_mode_display', config.modeDisplay);
    await prefs.setInt('widget_${widgetId}_last_api_fetch',
        DateTime.now().millisecondsSinceEpoch);

    // Render chart bitmap (simplified: just chart, no text overlay)
    try {
      final dataPoints = data['dataPoints'] as List<Map<String, dynamic>>? ?? [];

      final chartFile = await WidgetChartRenderer.render(
        widgetId: widgetId,
        dataPoints: dataPoints,
        widthDp: 230.0,
        heightDp: 80.0,
      );

      await prefs.setString(
          'widget_${widgetId}_chart_path', chartFile.path);
      await prefs.setInt('widget_${widgetId}_last_chart_render',
          DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Chart rendering failure is non-fatal; widget shows text only
    }

    // Trigger native widget update
    await updateAllWidgets();
  }

  /// Delete all data for a widget
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
  }
}
