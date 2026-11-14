import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';

import '../fixtures/test_fixtures.dart';

void main() {
  group('BridgeScope', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('scoped dependencies are invisible to the parent bridge', () {
      final scope = bridge.createScope();
      scope.registerSingleton<String>('scoped-value');

      expect(scope.get<String>(), 'scoped-value');
      expect(bridge.isRegistered<String>(), isFalse);
      expect(() => bridge.get<String>(),
          throwsA(isA<BridgeDependencyNotFoundException>()));
    });

    test('scope resolution falls back to parent bridge registrations', () {
      bridge.registerSingleton<String>('global-value');
      final scope = bridge.createScope();

      expect(scope.get<String>(), 'global-value');
      expect(scope.isRegistered<String>(), isTrue);
    });

    test('scope-local registration shadows the parent dependency', () {
      bridge.registerSingleton<String>('global');
      final scope = bridge.createScope();
      scope.registerSingleton<String>('scoped');

      expect(scope.get<String>(), 'scoped');
      expect(bridge.get<String>(), 'global');
    });

    test('independent scopes do not see each other', () {
      final scopeA = bridge.createScope();
      final scopeB = bridge.createScope();

      scopeA.registerSingleton<int>(1);
      scopeB.registerSingleton<int>(2);

      expect(scopeA.get<int>(), 1);
      expect(scopeB.get<int>(), 2);
    });

    test('supports lazy singleton, factory and named instances', () {
      final scope = bridge.createScope();
      var lazyCalls = 0;
      scope.registerLazySingleton<UserRepository>(() {
        lazyCalls++;
        return UserRepository();
      });
      scope.registerFactory<String>(
          () => 'factory-${DateTime.now().microsecond}');
      scope.registerSingleton<String>('named-a', instanceName: 'a');
      scope.registerSingleton<String>('named-b', instanceName: 'b');

      final first = scope.get<UserRepository>();
      expect(identical(first, scope.get<UserRepository>()), isTrue);
      expect(lazyCalls, 1);

      expect(scope.get<String>(instanceName: 'a'), 'named-a');
      expect(scope.get<String>(instanceName: 'b'), 'named-b');
      expect(scope.get<String>(), isNot(equals('named-a')));
    });

    test('duplicate registration throws unless override is true', () {
      final scope = bridge.createScope();
      scope.registerSingleton<int>(1);

      expect(
        () => scope.registerSingleton<int>(2),
        throwsA(isA<BridgeDependencyAlreadyRegisteredException>()),
      );

      scope.registerSingleton<int>(2, override: true);
      expect(scope.get<int>(), 2);
    });

    test('tryGet and call syntax work with scope fallback', () {
      bridge.registerSingleton<String>('from-bridge');
      final scope = bridge.createScope();
      scope.registerSingleton<int>(42);

      expect(scope.tryGet<String>(), 'from-bridge');
      expect(scope.tryGet<double>(), isNull);
      expect(scope<int>(), 42);
    });

    test('dispose cleans up all scoped dependencies and runs onDispose',
        () async {
      var disposeCount = 0;
      final scope = bridge.createScope();
      scope.registerSingleton<UserRepository>(
        UserRepository(),
        onDispose: (_) => disposeCount++,
      );
      scope.registerSingleton<String>('temp');

      await scope.dispose();

      expect(scope.isDisposed, isTrue);
      expect(disposeCount, 1);
      expect(() => scope.get<UserRepository>(), throwsStateError);
      expect(() => scope.registerSingleton<int>(1), throwsStateError);

      // Parent bridge untouched
      expect(bridge.isRegistered<UserRepository>(), isFalse);
    });

    test('dispose is idempotent', () async {
      final scope = bridge.createScope();
      await scope.dispose();
      await scope.dispose();
      expect(scope.isDisposed, isTrue);
    });

    test('scope factories can consume parent bridge singletons', () {
      bridge.registerSingleton<UserRepository>(UserRepository());
      final scope = bridge.createScope();

      scope.registerLazySingleton<String>(
        () => 'user:${scope.get<UserRepository>().getUser()}',
      );

      expect(scope.get<String>(), 'user:user_42');
      expect(bridge.isRegistered<String>(), isFalse);
    });
  });
}
