class AppConstants {
  // SharedPreferences Keys
  static const String keyAccessToken = 'access_token';
  static const String keyTokenExpiresAt = 'token_expires_at';
  static const String keyClientId = 'client_id';
  static const String keyClientSecret = 'client_secret';
  
  static const String keyThemeMode = 'theme_mode_pref';
  static const String keyThemeColor = 'theme_color_pref';
  static const String keyUseDynamicColor = 'use_dynamic_color_pref';
  static const String keyCompareTarget = 'compare_target_pref';

  static const String keyActiveWidgetIds = 'active_widget_ids';

  // Database Constants
  static const String dbName = 'osu_stats.db';
  static const String tableUserCache = 'user_cache';
  
  static const String colId = 'id';
  static const String colUserId = 'user_id';
  static const String colUsername = 'username';
  static const String colCountryCode = 'country_code';
  static const String colBeatmapPlaycountsCount = 'beatmap_playcounts_count';
  static const String colFollowerCount = 'follower_count';
  static const String colUserAchievements = 'user_achievements';
  static const String colOsuJson = 'osu_json';
  static const String colTaikoJson = 'taiko_json';
  static const String colFruitsJson = 'fruits_json';
  static const String colManiaJson = 'mania_json';
  static const String colUpdatedAt = 'updated_at';

  // Widget Time Ranges
  static const String range1Day = '1天';
  static const String range3Days = '3天';
  static const String range7Days = '7天';
  static const String range1Month = '1个月';
  static const String rangeCustom = '自定义';
  static const String rangeAll = '全部';
}
