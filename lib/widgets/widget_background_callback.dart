import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../services/osu_api_service.dart';

/// Background callback for home_widget WorkManager updates.
/// Runs in a limited background isolate - can do HTTP and SharedPreferences
/// but cannot render charts (no dart:ui access).
/// IMPORTANT: Do NOT import utils.dart or any module that references dart:ui.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // Bug 1 fix: read active_widget_ids as JSON string (matches Kotlin and service)
    final activeIdsStr = prefs.getString('active_widget_ids');
    List<String> activeIds = [];
    if (activeIdsStr != null && activeIdsStr.isNotEmpty) {
      try {
        activeIds = (jsonDecode(activeIdsStr) as List).cast<String>();
      } catch (_) {}
    }

    for (final idStr in activeIds) {
      final widgetId = int.tryParse(idStr);
      if (widgetId == null) continue;

      // Load config
      final username = prefs.getString('widget_${widgetId}_username');
      final modeDisplay = prefs.getString('widget_${widgetId}_mode_display');
      final fieldKey = prefs.getString('widget_${widgetId}_field_key');
      if (username == null || modeDisplay == null || fieldKey == null) continue;

      // Check cache - don't fetch if recent
      final lastFetch = prefs.getInt('widget_${widgetId}_last_api_fetch') ?? 0;
      if (lastFetch > 0) {
        final lastTime = DateTime.fromMillisecondsSinceEpoch(lastFetch);
        if (DateTime.now().difference(lastTime).inMinutes < 15) continue;
      }

      try {
        // Fetch fresh data from osu! API
        final api = OsuApiService();
        final data = await api.getUserData(username, modeDisplay);
        final stats = data['statistics'] as Map<String, dynamic>? ?? {};
        final currentValue = stats[fieldKey];

        // Save updated values
        await prefs.setInt('widget_${widgetId}_last_api_fetch',
            DateTime.now().millisecondsSinceEpoch);

        if (currentValue != null) {
          // Bug 6 fix: proper formatting for all stat types
          String formattedValue;
          if (fieldKey == 'accuracy') {
            formattedValue =
                '${((currentValue as num).toDouble() * 100).toStringAsFixed(2)}%';
          } else if (fieldKey == 'play_time') {
            formattedValue = _formatDurationCompact((currentValue as num).toInt());
          } else if (fieldKey == 'global_rank' || fieldKey == 'country_rank') {
            formattedValue = '#${_formatNumCompact(currentValue)}';
          } else {
            formattedValue = _formatNumCompact(currentValue);
          }
          await prefs.setString(
              'widget_${widgetId}_current_value', formattedValue);
        }
      } catch (_) {
        // Silently fail - widget keeps showing previous data
      }
    }

    // Trigger widget update for both widget sizes
    for (final name in ['OsustatsWidgetProvider', 'OsustatsWidgetProvider4x2']) {
      try {
        await HomeWidget.updateWidget(
          name: name,
          androidName: name,
        );
      } catch (_) {}
    }
  } catch (_) {
    // Background callback failures are silent
  }
}

/// Compact number formatting (inlined to avoid importing utils.dart / dart:ui)
String _formatNumCompact(dynamic val) {
  if (val == null) return '-';
  num? numVal;
  if (val is num) {
    numVal = val;
  } else {
    numVal = num.tryParse(val.toString());
  }

  if (numVal == null) return '-';
  
  if (numVal.abs() >= 1000000000) {
    return '${(numVal / 1000000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}B';
  } else if (numVal.abs() >= 1000000) {
    return '${(numVal / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
  } else if (numVal.abs() >= 10000) { // Compress >= 10k or maybe >= 1000? Let's say >= 10k to keep 4 digits. Actually, 1k is fine too, but usually 4 digits fit. Let's do >= 10000 for K, or >= 1000? Let's just do >= 1000.
    return '${(numVal / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
  }

  // Fallback to normal comma formatting for smaller numbers
  final str = val is int ? val.toString() : val.toString();
  final hasSign = str.startsWith('-') || str.startsWith('+');
  final sign = hasSign ? str[0] : '';
  final rest = hasSign ? str.substring(1) : str;

  final dotIndex = rest.indexOf('.');
  final intPart = dotIndex >= 0 ? rest.substring(0, dotIndex) : rest;
  final decPart = dotIndex >= 0 ? rest.substring(dotIndex) : '';

  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  return '$sign$buffer$decPart';
}

/// Compact duration formatting (inlined to avoid importing utils.dart / dart:ui)
String _formatDurationCompact(int seconds) {
  if (seconds < 0) return '0秒';
  const daySeconds = 86400;
  const hourSeconds = 3600;
  const minuteSeconds = 60;

  int days = seconds ~/ daySeconds;
  int hours = (seconds % daySeconds) ~/ hourSeconds;
  int minutes = (seconds % hourSeconds) ~/ minuteSeconds;
  int secs = seconds % minuteSeconds;

  final parts = <String>[];
  if (days > 0) parts.add('$days天');
  if (hours > 0) parts.add('$hours小时');
  if (minutes > 0) parts.add('$minutes分');
  if (secs > 0) parts.add('$secs秒');

  if (parts.isEmpty) return '0秒';
  return parts.join(' ');
}
