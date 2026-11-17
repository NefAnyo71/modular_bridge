import 'package:modular_bridge/modular_bridge.dart';
import 'package:test/test.dart';

void main() {
  late ModularBridge bridge;
  late BridgeConfig config;

  setUp(() {
    config = BridgeConfig(
      environment: BridgeEnvironment.dev,
      commonValues: {
        'api.baseUrl': 'https://api.global.dev',
        'tenant': 'global',
      },
    );
    bridge = ModularBridge.createIsolated(config: config);
  });

  tearDown(() async {
    await bridge.dispose();
    config.dispose();
  });

  group('Scoped config overrides', () {
    test('scope override shadows global config for configValue', () {
      final scope = bridge.pushNewScope(scopeName: 'request');
      scope.setConfigValue('api.baseUrl', 'https://api.tenant-a.dev');

      expect(bridge.configValue<String>('api.baseUrl'),
          'https://api.tenant-a.dev');
      expect(scope.configValue<String>('api.baseUrl'),
          'https://api.tenant-a.dev');
      // The global config itself is untouched.
      expect(config.getString('api.baseUrl'), 'https://api.global.dev');
    });

    test('no scope active -> configValue reads global config', () {
      expect(bridge.configValue<String>('api.baseUrl'),
          'https://api.global.dev');
      expect(bridge.configValue<int>('missing', defaultValue: 42), 42);
    });

    test('child scope inherits ancestor overrides, own wins', () {
      final session = bridge.pushNewScope(scopeName: 'session');
      session.setConfigValue('tenant', 'tenant-a');
      session.setConfigValue('api.baseUrl', 'https://session.dev');

      final request = session.createChildScope(scopeName: 'request');
      request.setConfigValue('tenant', 'tenant-b');

      expect(request.configValue<String>('tenant'), 'tenant-b');
      expect(request.configValue<String>('api.baseUrl'),
          'https://session.dev');
      expect(session.configValue<String>('tenant'), 'tenant-a');
    });

    test('removeConfigValue restores the global value', () {
      final scope = bridge.pushNewScope(scopeName: 'request');
      scope.setConfigValue('tenant', 'tenant-a');
      expect(scope.configValue<String>('tenant'), 'tenant-a');

      expect(scope.removeConfigValue('tenant'), isTrue);
      expect(scope.removeConfigValue('tenant'), isFalse);
      expect(scope.configValue<String>('tenant'), 'global');
    });

    test('type mismatch on override throws BridgeConfigTypeMismatchException',
        () {
      final scope = bridge.pushNewScope(scopeName: 'request');
      scope.setConfigValue('tenant', 123);

      expect(
        () => scope.configValue<String>('tenant'),
        throwsA(isA<BridgeConfigTypeMismatchException>()),
      );
    });

    test('missing key without default throws BridgeConfigKeyNotFoundException',
        () {
      final scope = bridge.pushNewScope(scopeName: 'request');
      expect(
        () => scope.configValue<String>('nope'),
        throwsA(isA<BridgeConfigKeyNotFoundException>()),
      );
    });

    test('config-bound dependency inside scope re-decodes on override change',
        () async {
      final scope = bridge.pushNewScope(scopeName: 'tenant');
      scope.setConfigValue('tenant', 'tenant-a');
      bridge.registerConfigBinding<String>(
        configKey: 'tenant',
        decoder: (v) => 'tenant:$v',
      );

      expect(bridge.get<String>(), 'tenant:tenant-a');

      scope.setConfigValue('tenant', 'tenant-b');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(bridge.get<String>(), 'tenant:tenant-b');
    });

    test('root config binding ignores scope overrides', () async {
      bridge.registerConfigBinding<String>(
        configKey: 'tenant',
        decoder: (v) => 'tenant:$v',
      );
      expect(bridge.get<String>(), 'tenant:global');

      final scope = bridge.pushNewScope(scopeName: 'request');
      scope.setConfigValue('tenant', 'tenant-a');
      await Future<void>.delayed(Duration.zero);

      // The root binding was registered with no scope, so it keeps the
      // global value even while a scope override exists.
      expect(bridge.get<String>(), 'tenant:global');
      expect(scope.configValue<String>('tenant'), 'tenant-a');
    });

    test('overrides die with the scope', () async {
      final scope = bridge.pushNewScope(scopeName: 'request');
      scope.setConfigValue('tenant', 'tenant-a');
      expect(scope.configValue<String>('tenant'), 'tenant-a');

      await bridge.popScope();

      expect(bridge.configValue<String>('tenant'), 'global');
      expect(config.getString('api.baseUrl'), 'https://api.global.dev');
    });

    test('setConfigValue on disposed scope throws StateError', () async {
      final scope = bridge.pushNewScope(scopeName: 'request');
      await bridge.popScope();

      expect(() => scope.setConfigValue('tenant', 'x'), throwsStateError);
    });
  });
}
