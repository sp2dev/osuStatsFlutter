import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import 'pages/main_page.dart';
import 'pages/history_page.dart';
import 'pages/profile_page.dart';
import 'pages/widget_config_page.dart';
import 'services/widget_data_service.dart';
import 'widgets/widget_background_callback.dart';
import 'utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register home_widget background callback for periodic updates
  HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Load saved theme settings
  final prefs = await SharedPreferences.getInstance();
  final themeModeIndex = prefs.getInt('theme_mode_pref') ?? AppThemeMode.system.index;
  final colorValue = prefs.getInt('theme_color_pref') ?? const Color(0xFFFF66AA).toARGB32();
  final useDynamic = prefs.getBool('use_dynamic_color_pref') ?? false;

  themeSettingsNotifier.value = ThemeSettings(
    themeMode: AppThemeMode.values[themeModeIndex],
    seedColor: Color(colorValue),
    useDynamicColor: useDynamic,
  );

  final compareTargetIndex = prefs.getInt('compare_target_pref') ?? CompareTarget.lastQuery.index;
  compareTargetNotifier.value = CompareTarget.values[compareTargetIndex];

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeSettings>(
      valueListenable: themeSettingsNotifier,
      builder: (context, settings, _) {
        ThemeMode currentThemeMode;
        switch (settings.themeMode) {
          case AppThemeMode.system:
            currentThemeMode = ThemeMode.system;
            break;
          case AppThemeMode.light:
            currentThemeMode = ThemeMode.light;
            break;
          case AppThemeMode.dark:
            currentThemeMode = ThemeMode.dark;
            break;
        }

        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            ColorScheme lightScheme;
            ColorScheme darkScheme;

            if (settings.useDynamicColor && lightDynamic != null && darkDynamic != null) {
              lightScheme = lightDynamic.harmonized();
              darkScheme = darkDynamic.harmonized();
            } else {
              lightScheme = ColorScheme.fromSeed(
                seedColor: settings.seedColor,
                brightness: Brightness.light,
              );
              darkScheme = ColorScheme.fromSeed(
                seedColor: settings.seedColor,
                brightness: Brightness.dark,
              );
            }

            return MaterialApp(
              title: 'osu! Stats',
              theme: ThemeData(
                colorScheme: lightScheme,
                useMaterial3: true,
              ),
              darkTheme: ThemeData(
                colorScheme: darkScheme,
                useMaterial3: true,
              ),
              themeMode: currentThemeMode,
              home: const HomePage(),
              debugShowCheckedModeBanner: false,
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _currentNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for pending widget configuration after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingWidgetConfig();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWidgetData();
      _checkPendingWidgetConfig();
    }
  }

  Future<void> _checkPendingWidgetConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // Reload from disk to pick up values written by Kotlin's native commit()
    // (Flutter caches SharedPreferences in memory, so cross-process writes
    // are invisible until we explicitly reload)
    await prefs.reload();

    // Check for widget tap: the native provider writes last_tapped_widget_id
    // when the user taps an unconfigured widget on the home screen.
    final tappedId = prefs.getInt('last_tapped_widget_id');
    if (tappedId != null && tappedId != 0) {
      await prefs.remove('last_tapped_widget_id');
      // Also remove the pending marker the provider wrote
      await prefs.remove('pending_widget_$tappedId');
      if (!mounted) return;
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => WidgetConfigPage(initialWidgetId: tappedId),
        ),
      );
      if (result == true && mounted) {
        _refreshWidgetData();
      }
      return;
    }

    // Check for old-style pending widget config (from previous version)
    final pendingWidgetId = prefs.getInt('pending_widget_config_id');
    if (pendingWidgetId != null && pendingWidgetId != 0) {
      await prefs.remove('pending_widget_config_id');
      if (!mounted) return;
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => WidgetConfigPage(initialWidgetId: pendingWidgetId),
        ),
      );
      if (result == true && mounted) {
        _refreshWidgetData();
      }
    }
  }

  Future<void> _refreshWidgetData() async {
    try {
      await WidgetDataService().refreshAllWidgetCharts();
    } catch (_) {
      // Silently fail — widgets keep showing last good data
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentNavIndex,
        children: const [
          MainPage(),
          HistoryPage(),
          ProfilePage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (index) {
          setState(() {
            _currentNavIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '历史记录'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
