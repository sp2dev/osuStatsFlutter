import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:osu_stats/main.dart';
import 'package:osu_stats/providers/app_state_provider.dart';

void main() {
  testWidgets('App renders home page', (WidgetTester tester) async {
    // MyApp's Consumer requires an AppStateProvider above it; main() wires
    // this up via ChangeNotifierProvider.value, so the test must too.
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: AppStateProvider(),
        child: const MyApp(),
      ),
    );
    expect(find.text('首页'), findsWidgets);
  });
}
