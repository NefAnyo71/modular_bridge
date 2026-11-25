import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';
import 'package:modular_bridge_example/analytics/analytics_module.dart';
import 'package:modular_bridge_example/auth/auth_module.dart';
import 'package:modular_bridge_example/cart/cart_module.dart';
import 'package:modular_bridge_example/core/core_module.dart';
import 'package:modular_bridge_example/home/home_module.dart';
import 'package:modular_bridge_example/main.dart';

void main() {
  tearDown(() async {
    await ModularBridge.I.reset();
    ModularBridge.resetInstance();
  });

  testWidgets('Example app boots and renders all tabs', (tester) async {
    final config = BridgeConfig(
      environment: BridgeEnvironment.dev,
      environmentValues: {
        BridgeEnvironment.dev: {
          'api': {'baseUrl': 'https://dev.api.test', 'timeoutMs': 5000},
          'enableBiometrics': false,
          'retryCount': 3,
        },
      },
    );

    ModularBridge.I.setConfig(config);
    await ModularBridge.I.registerModules([
      CoreModule(),
      AnalyticsModule(),
      AuthModule(),
      HomeModule(),
      CartModule(),
    ]);
    // NB: warmup() is skipped here — it awaits the eager SessionStore's
    // Future.delayed, which never fires inside the fake-async test zone.

    await tester.pumpWidget(const ModularBridgeExampleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ModularBridge'), findsOneWidget);
    expect(find.text('DEV'), findsWidgets);

    // Events tab
    await tester.tap(find.text('Events'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Event Bus'), findsOneWidget);

    // Inspector tab — module cards live in a lazy ListView, scroll to them.
    await tester.tap(find.text('Inspector'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('CoreModule'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('CartModule'), 200);
    await tester.pump();
    expect(find.text('CartModule'), findsOneWidget);
    expect(find.text('HomeModule'), findsOneWidget);

    // Config tab
    await tester.tap(find.text('Config'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Runtime flavor hot-switching'), findsOneWidget);
  });
}
