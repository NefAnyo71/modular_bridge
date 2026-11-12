import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';
import 'package:modular_bridge_example/auth/auth_module.dart';
import 'package:modular_bridge_example/core/core_module.dart';
import 'package:modular_bridge_example/home/home_module.dart';
import 'package:modular_bridge_example/main.dart';

void main() {
  testWidgets('Example app boots and renders ModularBridge Showcase', (WidgetTester tester) async {
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
      AuthModule(),
      HomeModule(),
    ]);

    await tester.pumpWidget(
      const ModularBridgeProvider(
        child: ModularBridgeExampleApp(),
      ),
    );

    expect(find.text('ModularBridge Architecture'), findsOneWidget);
    expect(find.text('DEV'), findsWidgets);
  });
}
