import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge_flutter/modular_bridge_flutter.dart';

Widget _harness(ModularBridge bridge) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      width: 500,
      height: 2400,
      child: ModularBridgeInspector(bridge: bridge),
    ),
  );
}

void main() {
  group('ModularBridgeInspector', () {
    testWidgets('renders diagnostics for a populated bridge', (tester) async {
      final bridge = ModularBridge.createIsolated();
      bridge.registerSingleton<String>('inspector-value');
      addTearDown(bridge.reset);

      await tester.pumpWidget(_harness(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Bridge Diagnostics'), findsOneWidget);
      expect(find.textContaining('Resolutions'), findsWidgets);
      expect(find.textContaining('String'), findsWidgets);
      // Registration happened before the inspector subscribed, so the
      // event feed stays empty while the registration is listed.
      expect(find.text('Registrations (1)'), findsOneWidget);
      expect(find.text('Recent Dependency Events (0)'), findsOneWidget);
    });

    testWidgets('health check button reports module results', (tester) async {
      final bridge = ModularBridge.createIsolated();
      addTearDown(bridge.reset);

      await tester.pumpWidget(_harness(bridge));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Health Check'));
      await tester.pumpAndSettle();

      // No modules registered → empty-state message appears.
      expect(find.text('No modules are currently registered.'), findsOneWidget);
    });

    testWidgets('updates when dependency events arrive', (tester) async {
      final bridge = ModularBridge.createIsolated();
      addTearDown(bridge.reset);

      await tester.pumpWidget(_harness(bridge));
      await tester.pumpAndSettle();

      expect(find.text('Recent Dependency Events (0)'), findsOneWidget);

      bridge.registerSingleton<int>(42);
      await tester.pumpAndSettle();

      expect(find.text('Recent Dependency Events (1)'), findsOneWidget);
      expect(find.textContaining('int'), findsWidgets);
    });
  });
}
