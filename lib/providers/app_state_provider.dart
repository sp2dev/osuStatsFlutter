import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

enum AppThemeMode { system, light, dark }

enum CompareTarget {
  lastQuery,
  todayEarliest,
  yesterdayLatest,
}

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

class AppStateProvider extends ChangeNotifier {
  ThemeSettings _themeSettings = ThemeSettings(
    themeMode: AppThemeMode.system,
    seedColor: const Color(0xFF3498DB),
    useDynamicColor: true,
  );
  CompareTarget _compareTarget = CompareTarget.lastQuery;
  int _historyUpdateTrigger = 0;

  ThemeSettings get themeSettings => _themeSettings;
  CompareTarget get compareTarget => _compareTarget;
  int get historyUpdateTrigger => _historyUpdateTrigger;

  void notifyHistoryUpdated() {
    _historyUpdateTrigger++;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final themeModeIndex = prefs.getInt(AppConstants.keyThemeMode) ?? AppThemeMode.system.index;
    final colorValue = prefs.getInt(AppConstants.keyThemeColor) ?? const Color(0xFF3498DB).toARGB32();
    final useDynamic = prefs.getBool(AppConstants.keyUseDynamicColor) ?? false;
    
    _themeSettings = ThemeSettings(
      themeMode: AppThemeMode.values[themeModeIndex],
      seedColor: Color(colorValue),
      useDynamicColor: useDynamic,
    );

    final compareTargetIndex = prefs.getInt(AppConstants.keyCompareTarget) ?? CompareTarget.lastQuery.index;
    _compareTarget = CompareTarget.values[compareTargetIndex];

    notifyListeners();
  }

  Future<void> updateThemeSettings({
    AppThemeMode? themeMode,
    Color? seedColor,
    bool? useDynamicColor,
  }) async {
    _themeSettings = _themeSettings.copyWith(
      themeMode: themeMode,
      seedColor: seedColor,
      useDynamicColor: useDynamicColor,
    );
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (themeMode != null) {
      await prefs.setInt(AppConstants.keyThemeMode, themeMode.index);
    }
    if (seedColor != null) {
      await prefs.setInt(AppConstants.keyThemeColor, seedColor.toARGB32());
    }
    if (useDynamicColor != null) {
      await prefs.setBool(AppConstants.keyUseDynamicColor, useDynamicColor);
    }
  }

  Future<void> updateCompareTarget(CompareTarget target) async {
    _compareTarget = target;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.keyCompareTarget, target.index);
  }
}
