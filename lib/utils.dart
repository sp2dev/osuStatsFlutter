import 'dart:convert';

import 'package:flutter/material.dart';

String formatNum(dynamic val) {
  if (val == null) return '-';
  final str = val.toString();
  if (str.isEmpty) return '-';
  
  final hasSign = str.startsWith('-') || str.startsWith('+');
  final sign = hasSign ? str[0] : '';
  final rest = hasSign ? str.substring(1) : str;
  
  // Split integer and decimal parts to avoid inserting commas into decimals
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

String formatNumCompact(dynamic val) {
  if (val == null) return '-';
  num? numVal;
  if (val is num) {
    numVal = val;
  } else {
    numVal = num.tryParse(val.toString());
  }

  if (numVal == null) return '-';
  
  if (numVal.abs() >= 1000000) {
    return '${(numVal / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
  } else if (numVal.abs() >= 10000) {
    return '${(numVal / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
  }

  return formatNum(val);
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
    // formatDuration takes a magnitude; the sign must be added explicitly
    // because diff may be negative.
    final signStr = diff > 0 ? '+' : '-';
    text = '$signStr${formatDuration(diff.abs().toInt())}';
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
          ? Image.asset(
              'assets/Flags/$country.png', 
              width: 28, 
              height: 28, 
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.public, size: 28),
            )
          : const Icon(Icons.public),
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

// Predefined colors for settings
const List<Map<String, dynamic>> predefinedColors = [
  {'name': 'osu! 粉', 'color': Color(0xFFFF66AA)},
  {'name': '晴空蓝', 'color': Color(0xFF3498DB)},
  {'name': '翡翠绿', 'color': Color(0xFF2ECC71)},
  {'name': '落日橙', 'color': Color(0xFFE67E22)},
  {'name': '深邃紫', 'color': Color(0xFF9B59B6)},
  {'name': '烈焰红', 'color': Color(0xFFE74C3C)},
];

/// Shared transformation of raw history rows into chart data points.
///
/// Centralizes stat normalization (accuracy → %, play_time → hours, rank
/// inversion for "higher is better" charts) previously duplicated between the
/// in-app chart page and the home-screen widget renderer.
///
/// Input order is preserved: pass history in chronological order for line
/// charts. Malformed rows are skipped rather than crashing the chart.
List<Map<String, dynamic>> buildDataPoints({
  required List<Map<String, dynamic>> history,
  required String modeKey,
  required String fieldKey,
  int? startTimeMs,
}) {
  final dataPoints = <Map<String, dynamic>>[];

  for (final record in history) {
    final updatedAt = record['updated_at'] as int;
    if (startTimeMs != null && updatedAt < startTimeMs) {
      continue;
    }

    final jsonStr = record[modeKey] as String?;
    if (jsonStr == null || jsonStr.isEmpty) continue;
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final stats = data['statistics'] as Map<String, dynamic>? ?? {};
      final value = stats[fieldKey];
      if (value == null) continue;

      num numValue = value as num;
      if (fieldKey == 'accuracy') {
        numValue = numValue * 100;
      } else if (fieldKey == 'play_time') {
        numValue = numValue / 3600.0; // hours
      } else if (fieldKey == 'global_rank' || fieldKey == 'country_rank') {
        numValue = -numValue; // invert so "higher is better"
      }

      dataPoints.add({
        // Epoch ms (int) keeps the payload trivially isolate-sendable;
        // callers convert to DateTime when they need one.
        'time': updatedAt,
        'value': numValue.toDouble(),
      });
    } catch (_) {
      // Skip malformed history entries.
    }
  }

  return dataPoints;
}

/// [compute] entry point for [buildDataPoints]: runs the parse off the main
/// isolate. `input` must be isolate-sendable.
List<Map<String, dynamic>> computeDataPoints(Map<String, dynamic> input) {
  return buildDataPoints(
    history: (input['history'] as List).cast<Map<String, dynamic>>(),
    modeKey: input['modeKey'] as String,
    fieldKey: input['fieldKey'] as String,
    startTimeMs: input['startTimeMs'] as int?,
  );
}

