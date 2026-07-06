import 'package:flutter/widgets.dart';
import '../services/widget_data_service.dart';

/// Background callback for home_widget updates.
/// Runs in a limited background isolate.
/// Using WidgetDataService allows us to save to DB and render chart headless-ly.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await WidgetDataService().refreshAllWidgetCharts();
  } catch (_) {
    // Background callback failures are silent
  }
}
