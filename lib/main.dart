import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/main_page.dart';
import 'pages/history_page.dart';
import 'pages/profile_page.dart';
import 'pages/widget_config_page.dart';
import 'pages/chart_page.dart';
import 'package:animations/animations.dart';

import 'services/widget_data_service.dart';
import 'services/database_service.dart';
import 'widgets/widget_background_callback.dart';
import 'providers/app_state_provider.dart';
import 'core/logger.dart';

@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      await WidgetDataService().refreshAllWidgetCharts();
    } catch (e, stack) {
      appLogger.e('Background task failed', error: e, stackTrace: stack);
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (!kIsWeb && Platform.isAndroid) {
    try {
      await Workmanager().initialize(workmanagerCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        'widget_auto_refresh',
        'widgetRefreshTask',
        frequency: const Duration(minutes: 60),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 5),
      );
    } catch (e, stack) {
      appLogger.e('Failed to init workmanager', error: e, stackTrace: stack);
    }
  }

  final appStateProvider = AppStateProvider();
  await appStateProvider.loadSettings();

  runApp(
    ChangeNotifierProvider.value(
      value: appStateProvider,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        final settings = provider.themeSettings;
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

    await prefs.reload();

    final tappedId = prefs.getInt('last_tapped_widget_id');
    if (tappedId != null && tappedId != 0) {
      await prefs.remove('last_tapped_widget_id');
      await prefs.remove('pending_widget_$tappedId');
      
      try {
        final config = await WidgetDataService().loadWidgetConfig(tappedId);
        if (config != null) {
          final db = DatabaseService();
          final users = await db.getAllUsers();
          int? userId;
          for (final u in users) {
            if (u['username'] == config.username) {
              userId = u['user_id'] as int?;
              break;
            }
          }
          if (userId != null) {
            final history = await db.getRecordsForUser(userId);
            if (!mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChartPage(
                  username: config.username,
                  statLabel: config.fieldLabel,
                  fieldKey: config.fieldKey,
                  modeKey: config.modeKey,
                  history: history,
                ),
              ),
            );
            return;
          }
        }
      } catch (e, stack) {
        appLogger.e('Error loading widget config for $tappedId', error: e, stackTrace: stack);
      }

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
    } catch (e, stack) {
      appLogger.e('Widget data refresh failed in foreground', error: e, stackTrace: stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageTransitionSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation, secondaryAnimation) {
          return FadeThroughTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            child: child,
          );
        },
        child: IndexedStack(
          key: ValueKey<int>(_currentNavIndex),
          index: _currentNavIndex,
          children: const [
            MainPage(),
            HistoryPage(),
            ProfilePage(),
          ],
        ),
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
