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

  if (days > 0) {
    if (hours > 0) return '$days 天 $hours 小时 $minutes 分钟 $secs 秒';
    return '$days 天';
  } else if (hours > 0) {
    if (minutes > 0) return '$hours 小时 $minutes 分钟 $secs 秒';
    return '$hours 小时';
  } else if (minutes > 0) {
    if (secs > 0) return '$minutes 分钟 $secs 秒';
    return '$minutes 分钟';
  } else {
    return '$secs 秒';
  }
}

List<Map<String, dynamic>> buildStatsItems(Map<String, dynamic> data) {
  final stats = data['statistics'] as Map<String, dynamic>? ?? {};

  final accuracy = stats['accuracy'] as num?;
  final accuracyStr = accuracy != null
      ? '${(accuracy * 100).toStringAsFixed(2)}%'
      : '-';

  final playtime = stats['play_time'] as int? ?? 0;
  final country = data['country_code'];

  return [
    {
      'label': 'pp',
      'value': stats['pp'].toString(),
      'icon': ImageIcon(AssetImage('assets/osulogo.png'), size: 36),
    },
    {
      'label': '总排名',
      'value': stats['global_rank'] != null
          ? '#${formatNum(stats['global_rank'])}'
          : '-',
      'icon': Icons.public,
    },
    {
      'label': '地区排名',
      'value': stats['country_rank'] != null
          ? '#${formatNum(stats['country_rank'])}'
          : '-',
      'icon': country != null
          ? Image.asset('assets/Flags/$country.png', width: 36)
          : Icons.flag,
    },
    {
      'label': '准确率',
      'value': accuracyStr,
      'icon': ImageIcon(AssetImage('assets/accuracy.png'), size: 36),
    },
    {
      'label': '总命中次数',
      'value': formatNum(stats['total_hits']),
      'icon': ImageIcon(AssetImage('assets/hits.png'), size: 36),
    },
    {
      'label': '计分成绩总分',
      'value': formatNum(stats['ranked_score']),
      'icon': Icons.emoji_events,
    },
    {
      'label': '总分数',
      'value': formatNum(stats['total_score']),
      'icon': Icons.scoreboard,
    },
    {
      'label': '游玩次数',
      'value': formatNum(stats['play_count']),
      'icon': Icons.play_circle,
    },
    {
      'label': '游玩时间',
      'value': formatDuration(playtime),
      'icon': Icons.timer,
    },
  ];
}
