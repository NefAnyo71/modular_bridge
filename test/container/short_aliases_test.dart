import 'package:test/test.dart';
import 'package:modular_bridge/modular_bridge.dart';

void main() {
  group('Short registration aliases', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated(
        config: BridgeConfig(
          environment: BridgeEnvironment.dev,
          commonValues: const {'greeting': 'hello'},
        ),
      );
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('singleton resolves the exact instance', () {
      final repo = Object();
      bridge.singleton<Object>(repo);
      expect(identical(bridge.get<Object>(), repo), isTrue);
    });

    test('lazySingleton creates once on first get', () {
      var builds = 0;
      bridge.lazySingleton<int>(() => ++builds);
      expect(bridge.get<int>(), 1);
      expect(bridge.get<int>(), 1);
      expect(builds, 1);
    });

    test('transient returns a new instance per get', () {
      var builds = 0;
      bridge.transient<int>(() => ++builds);
      expect(bridge.get<int>(), 1);
      expect(bridge.get<int>(), 2);
    });

    test('asyncSingleton resolves via getAsync and shares the future', () {
      bridge.asyncSingleton<String>(() async => 'async-value');
      expect(bridge.getAsync<String>(), completion('async-value'));
    });

    test('bind decodes a config value into a lazy singleton', () {
      bridge.bind<String>(
        configKey: 'greeting',
        decoder: (value) => 'hi-$value',
      );
      expect(bridge.get<String>(), 'hi-hello');
    });

    test('aliases honour instanceName and override', () async {
      bridge.singleton<String>('first', instanceName: 'named');
      expect(bridge.get<String>(instanceName: 'named'), 'first');

      bridge.singleton<String>('second', instanceName: 'named', override: true);
      expect(bridge.get<String>(instanceName: 'named'), 'second');
      await bridge.reset();
    });

    test('scope aliases register inside the scope', () async {
      final scope = await bridge.createScopeAsync((s) {
        s.singleton<int>(7);
        s.lazySingleton<String>(() => 'lazy');
        s.transient<double>(() => 1.5);
        s.asyncSingleton<bool>(() async => true);
      });
      expect(scope.get<int>(), 7);
      expect(scope.get<String>(), 'lazy');
      expect(scope.get<double>(), 1.5);
      expect(await scope.getAsync<bool>(), isTrue);
      await scope.dispose();
    });
  });
}
