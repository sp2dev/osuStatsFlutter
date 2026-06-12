import 'package:flutter/material.dart';

String formatNum(dynamic val) {
  if (val == null) return '-';
  final str = val is int ? val.toString() : val.toString();
  if (str.isEmpty) return '-';
  final buffer = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
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
      'value': stats['pp'] != null ? stats['pp'].toString() : '-',
      'icon': const ImageIcon(AssetImage('assets/osulogo.png'), size: 36),
      'difference': _getDiffInfo(stats['pp'] as num?, prevStats?['pp'] as num?),
    },
    {
      'label': '总排名',
      'value': stats['global_rank'] != null
          ? '#${formatNum(stats['global_rank'])}'
          : '-',
      'icon': Icons.public,
      'difference': _getDiffInfo(stats['global_rank'] as num?, prevStats?['global_rank'] as num?, lowerIsBetter: true),
    },
    {
      'label': '地区排名',
      'value': stats['country_rank'] != null
          ? '#${formatNum(stats['country_rank'])}'
          : '-',
      'icon': country != null
          ? Image.asset('assets/Flags/$country.png', width: 36)
          : Icons.flag,
      'difference': _getDiffInfo(stats['country_rank'] as num?, prevStats?['country_rank'] as num?, lowerIsBetter: true),
    },
    {
      'label': '准确率',
      'value': accuracyStr,
      'icon': const ImageIcon(AssetImage('assets/accuracy.png'), size: 36),
      'difference': _getDiffInfo(stats['accuracy'] as num?, prevStats?['accuracy'] as num?, isPercent: true),
    },
    {
      'label': '总命中次数',
      'value': formatNum(stats['total_hits']),
      'icon': const ImageIcon(AssetImage('assets/hits.png'), size: 36),
      'difference': _getDiffInfo(stats['total_hits'] as num?, prevStats?['total_hits'] as num?),
    },
    {
      'label': '计分成绩总分',
      'value': formatNum(stats['ranked_score']),
      'icon': Icons.emoji_events,
      'difference': _getDiffInfo(stats['ranked_score'] as num?, prevStats?['ranked_score'] as num?),
    },
    {
      'label': '总分数',
      'value': formatNum(stats['total_score']),
      'icon': Icons.scoreboard,
      'difference': _getDiffInfo(stats['total_score'] as num?, prevStats?['total_score'] as num?),
    },
    {
      'label': '游玩次数',
      'value': formatNum(stats['play_count']),
      'icon': Icons.play_circle,
      'difference': _getDiffInfo(stats['play_count'] as num?, prevStats?['play_count'] as num?),
    },
    {
      'label': '游玩时间',
      'value': formatDuration(playtime),
      'icon': Icons.timer,
      'difference': _getDiffInfo(stats['play_time'] as num?, prevStats?['play_time'] as num?, isTime: true),
    },
  ];
}
