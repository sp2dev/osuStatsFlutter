import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

String formatNum(dynamic val) {
  if (val == null) return '-';
  final str = val is int ? val.toString() : val.toString();
  if (str.isEmpty) return '-';
  
  final hasSign = str.startsWith('-') || str.startsWith('+');
  final sign = hasSign ? str[0] : '';
  final digits = hasSign ? str.substring(1) : str;
  
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$sign$buffer';
}

String formatDuration(int seconds) {
  if (seconds < 0) return '0秒';

  const daySeconds = 86400;
  const hourSeconds = 3600;
  const minuteSeconds = 60;

  int days = seconds ~/ daySeconds;
  int hours = (seconds % daySeconds) ~/ hourSeconds;
  int minutes = (seconds % hourSeconds) ~/ minuteSeconds;
  int secs = seconds % minuteSeconds;

  final parts = <String>[];
  if (days > 0) parts.add('$days 天');
  if (hours > 0) parts.add('$hours 小时');
  if (minutes > 0) parts.add('$minutes 分钟');
  if (secs > 0) parts.add('$secs 秒');

  if (parts.isEmpty) return '0秒';
  return parts.join(' ');
}

Map<String, dynamic>? _getDiffInfo(num? current, num? previous, {bool lowerIsBetter = false, bool isPercent = false, bool isTime = false}) {
  if (current == null || previous == null) return null;
  final double diff = lowerIsBetter ? (previous - current).toDouble() : (current - previous).toDouble();
  if (diff == 0) return null;

  final isPositive = diff > 0;
  final sign = diff > 0 ? '+' : '';

  String text;
  if (isPercent) {
    text = '$sign${(diff * 100).toStringAsFixed(2)}%';
  } else if (isTime) {
    text = '$sign${formatDuration(diff.abs().toInt())}';
  } else {
    if (diff == diff.toInt()) {
      text = '$sign${formatNum(diff.toInt())}';
    } else {
      text = '$sign${diff.toStringAsFixed(2)}';
    }
  }

  return {
    'text': text,
    'isPositive': isPositive,
  };
}

List<Map<String, dynamic>> buildStatsItems(Map<String, dynamic> data, [Map<String, dynamic>? previousData]) {
  final stats = data['statistics'] as Map<String, dynamic>? ?? {};
  final prevStats = previousData != null
      ? (previousData['statistics'] as Map<String, dynamic>? ?? {})
      : null;

  final accuracy = stats['accuracy'] as num?;
  final accuracyStr = accuracy != null
      ? '${(accuracy * 100).toStringAsFixed(2)}%'
      : '-';

  final playtime = stats['play_time'] as int? ?? 0;
  final country = data['country_code'];

  return [
    {
      'label': 'pp',
      'fieldKey': 'pp',
      'value': stats['pp'] != null ? stats['pp'].toString() : '-',
      'icon': const ImageIcon(AssetImage('assets/osulogo.png')),
      'difference': _getDiffInfo(stats['pp'] as num?, prevStats?['pp'] as num?),
    },
    {
      'label': '总排名',
      'fieldKey': 'global_rank',
      'value': stats['global_rank'] != null
          ? '#${formatNum(stats['global_rank'])}'
          : '-',
      'icon': Icons.public,
      'difference': _getDiffInfo(stats['global_rank'] as num?, prevStats?['global_rank'] as num?, lowerIsBetter: true),
    },
    {
      'label': '地区排名',
      'fieldKey': 'country_rank',
      'value': stats['country_rank'] != null
          ? '#${formatNum(stats['country_rank'])}'
          : '-',
      'icon': country != null
          ? Image.asset('assets/Flags/$country.png', width: 28, height: 28, fit: BoxFit.contain)
          : Icons.flag,
      'difference': _getDiffInfo(stats['country_rank'] as num?, prevStats?['country_rank'] as num?, lowerIsBetter: true),
    },
    {
      'label': '准确率',
      'fieldKey': 'accuracy',
      'value': accuracyStr,
      'icon': const ImageIcon(AssetImage('assets/accuracy.png')),
      'difference': _getDiffInfo(stats['accuracy'] as num?, prevStats?['accuracy'] as num?, isPercent: true),
    },
    {
      'label': '总命中次数',
      'fieldKey': 'total_hits',
      'value': formatNum(stats['total_hits']),
      'icon': const ImageIcon(AssetImage('assets/hits.png')),
      'difference': _getDiffInfo(stats['total_hits'] as num?, prevStats?['total_hits'] as num?),
    },
    {
      'label': '计分成绩总分',
      'fieldKey': 'ranked_score',
      'value': formatNum(stats['ranked_score']),
      'icon': Icons.emoji_events,
      'difference': _getDiffInfo(stats['ranked_score'] as num?, prevStats?['ranked_score'] as num?),
    },
    {
      'label': '总分数',
      'fieldKey': 'total_score',
      'value': formatNum(stats['total_score']),
      'icon': Icons.scoreboard,
      'difference': _getDiffInfo(stats['total_score'] as num?, prevStats?['total_score'] as num?),
    },
    {
      'label': '游玩次数',
      'fieldKey': 'play_count',
      'value': formatNum(stats['play_count']),
      'icon': Icons.play_circle,
      'difference': _getDiffInfo(stats['play_count'] as num?, prevStats?['play_count'] as num?),
    },
    {
      'label': '游玩时间',
      'fieldKey': 'play_time',
      'value': formatDuration(playtime),
      'icon': Icons.timer,
      'difference': _getDiffInfo(stats['play_time'] as num?, prevStats?['play_time'] as num?, isTime: true),
    },
  ];
}

bool areStatsDifferent(Map<String, dynamic>? data1, Map<String, dynamic>? data2) {
  if (data1 == null && data2 == null) return false;
  if (data1 == null || data2 == null) return true;
  final stats1 = data1['statistics'] as Map<String, dynamic>? ?? {};
  final stats2 = data2['statistics'] as Map<String, dynamic>? ?? {};

  final fields = ['pp', 'global_rank', 'country_rank', 'accuracy', 'total_hits', 'ranked_score', 'total_score', 'play_count', 'play_time'];
  for (final field in fields) {
    if (stats1[field] != stats2[field]) return true;
  }
  return false;
}

enum AppThemeMode { system, light, dark }

class ThemeSettings {
  final AppThemeMode themeMode;
  final Color seedColor;
  final bool useDynamicColor;

  ThemeSettings({
    required this.themeMode,
    required this.seedColor,
    required this.useDynamicColor,
  });

  ThemeSettings copyWith({
    AppThemeMode? themeMode,
    Color? seedColor,
    bool? useDynamicColor,
  }) {
    return ThemeSettings(
      themeMode: themeMode ?? this.themeMode,
      seedColor: seedColor ?? this.seedColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    );
  }
}

final themeSettingsNotifier = ValueNotifier<ThemeSettings>(
  ThemeSettings(
    themeMode: AppThemeMode.system,
    seedColor: const Color(0xFFFF66AA),
    useDynamicColor: false,
  ),
);

// Predefined colors for settings
const List<Map<String, dynamic>> predefinedColors = [
  {'name': 'osu! 粉', 'color': Color(0xFFFF66AA)},
  {'name': '晴空蓝', 'color': Color(0xFF3498DB)},
  {'name': '翡翠绿', 'color': Color(0xFF2ECC71)},
  {'name': '落日橙', 'color': Color(0xFFE67E22)},
  {'name': '深邃紫', 'color': Color(0xFF9B59B6)},
  {'name': '烈焰红', 'color': Color(0xFFE74C3C)},
];


void updateThemeSettings({
  AppThemeMode? themeMode,
  Color? seedColor,
  bool? useDynamicColor,
}) async {
  final current = themeSettingsNotifier.value;
  final updated = current.copyWith(
    themeMode: themeMode,
    seedColor: seedColor,
    useDynamicColor: useDynamicColor,
  );
  themeSettingsNotifier.value = updated;

  final prefs = await SharedPreferences.getInstance();
  if (themeMode != null) {
    await prefs.setInt('theme_mode_pref', themeMode.index);
  }
  if (seedColor != null) {
    await prefs.setInt('theme_color_pref', seedColor.toARGB32());
  }
  if (useDynamicColor != null) {
    await prefs.setBool('use_dynamic_color_pref', useDynamicColor);
  }
}

enum CompareTarget {
  lastQuery,
  todayEarliest,
  yesterdayLatest,
}

final compareTargetNotifier = ValueNotifier<CompareTarget>(CompareTarget.lastQuery);

void updateCompareTarget(CompareTarget target) async {
  compareTargetNotifier.value = target;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('compare_target_pref', target.index);
}
