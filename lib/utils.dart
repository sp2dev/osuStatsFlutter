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
