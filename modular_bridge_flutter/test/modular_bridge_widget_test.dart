import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge_flutter/modular_bridge_flutter.dart';

void main() {
  group('Flutter Widget Integration', () {
    testWidgets(
        'ModularBridgeScope and BuildContext extensions resolve dependencies',
        (tester) async {
      final testBridge = ModularBridge.createIsolated();
      testBridge.registerSingleton<String>('Hello ModularBridge');
      addTearDown(testBridge.reset);

      late String resolvedValue;

      await tester.pumpWidget(
        ModularBridgeScope(
          bridge: testBridge,
          child: Builder(
            builder: (context) {
              resolvedValue = context.get<String>();
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolvedValue, 'Hello ModularBridge');
    });

    testWidgets('context.tryGet returns null for unregistered types',
        (tester) async {
      final testBridge = ModularBridge.createIsolated();
      addTearDown(testBridge.reset);

      late String? resolvedValue;

      await tester.pumpWidget(
        ModularBridgeScope(
          bridge: testBridge,
          child: Builder(
            builder: (context) {
              resolvedValue = context.tryGet<String>();
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolvedValue, isNull);
    });

    testWidgets(
        'ModularBridgeProvider rebuilds subtree on environment hot-switch',
        (tester) async {
      final config = BridgeConfig(
        environment: BridgeEnvironment.dev,
        environmentValues: {
          BridgeEnvironment.dev: {'envLabel': 'Development Mode'},
          BridgeEnvironment.prod: {'envLabel': 'Production Mode'},
        },
      );
      final testBridge = ModularBridge.createIsolated(config: config);
      addTearDown(() async {
        config.dispose();
        await testBridge.reset();
      });

      await tester.pumpWidget(
        ModularBridgeProvider(
          bridge: testBridge,
          child: Builder(
            builder: (context) {
              final label = context.config.getString('envLabel');
              return Directionality(
                textDirection: TextDirection.ltr,
                child: Text(label),
              );
            },
          ),
        ),
      );

      expect(find.text('Development Mode'), findsOneWidget);

      // Hot-switch to prod
      testBridge.config.switchEnvironment(BridgeEnvironment.prod);
      await tester.pump();

      expect(find.text('Production Mode'), findsOneWidget);
    });
  });
}
