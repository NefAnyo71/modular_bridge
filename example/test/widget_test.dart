import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';
import 'package:modular_bridge_example/analytics/analytics_module.dart';
import 'package:modular_bridge_example/auth/auth_module.dart';
import 'package:modular_bridge_example/cart/cart_module.dart';
import 'package:modular_bridge_example/core/core_module.dart';
import 'package:modular_bridge_example/home/home_module.dart';
import 'package:modular_bridge_example/main.dart';

void main() {
  testWidgets('Example app boots and renders ModularBridge Showcase with all tabs', (WidgetTester tester) async {
    final config = BridgeConfig(
      environment: BridgeEnvironment.dev,
      environmentValues: {
        BridgeEnvironment.dev: {
          'apiBaseUrl': 'https://dev.api.modularbridge.io',
          'apiTimeout': const Duration(seconds: 15),
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

    await tester.pumpWidget(
      const ProviderScope(
        child: ModularBridgeProvider(
          child: ModularBridgeExampleApp(),
        ),
      ),
    );

    expect(find.text('ModularBridge Architecture'), findsOneWidget);
    expect(find.text('DEV'), findsWidgets);

    // Switch to Event Console tab
    await tester.tap(find.byIcon(Icons.terminal_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('Event Bus Stream'), findsOneWidget);

    // Switch to Module Inspector tab
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pumpAndSettle();
    expect(find.text('CartModule'), findsOneWidget);
    expect(find.text('AnalyticsModule'), findsOneWidget);

    // Switch to Config Studio tab
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Runtime Flavor Hot-Switching'), findsOneWidget);
  });
}
