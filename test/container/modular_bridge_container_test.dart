import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';

import '../fixtures/test_fixtures.dart';

void main() {
  group('Dependency Injection & Lifecycle', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('registers and resolves eager singleton', () {
      final repo = UserRepository();
      bridge.registerSingleton<UserRepository>(repo);

      expect(bridge.isRegistered<UserRepository>(), isTrue);
      final resolved = bridge.get<UserRepository>();
      expect(identical(resolved, repo), isTrue);
      // Callable syntax check
      expect(identical(bridge<UserRepository>(), repo), isTrue);
    });

    test('registers and resolves lazy singleton on demand', () {
      var factoryCalls = 0;
      bridge.registerLazySingleton<UserRepository>(() {
        factoryCalls++;
        return UserRepository();
      });

      expect(factoryCalls, 0); // Not called until resolved
      final first = bridge.get<UserRepository>();
      expect(factoryCalls, 1);

      final second = bridge.get<UserRepository>();
      expect(factoryCalls, 1); // Cached instance
      expect(identical(first, second), isTrue);
    });

    test('registers and resolves factory producing fresh instances', () {
      var factoryCalls = 0;
      bridge.registerFactory<UserRepository>(() {
        factoryCalls++;
        return UserRepository();
      });

      final first = bridge.get<UserRepository>();
      final second = bridge.get<UserRepository>();

      expect(factoryCalls, 2);
      expect(identical(first, second), isFalse);
    });

    test('throws BridgeDependencyNotFoundException for unregistered type', () {
      expect(
        () => bridge.get<AuthService>(),
        throwsA(isA<BridgeDependencyNotFoundException>().having(
          (e) => e.message,
          'message',
          contains('No dependency registered for type \'AuthService\''),
        )),
      );
    });

    test('named lookup failure includes the instance name in the error', () {
      expect(
        () => bridge.get<String>(instanceName: 'missingName'),
        throwsA(isA<BridgeDependencyNotFoundException>().having(
          (e) => e.message,
          'message',
          contains('with name \'missingName\''),
        )),
      );
    });

    test('tryGet returns null when dependency is missing', () {
      expect(bridge.tryGet<AuthService>(), isNull);
    });

    test('tryGet returns the resolved instance when dependency is registered', () {
      bridge.registerSingleton<String>('named-value', instanceName: 'token');

      expect(bridge.tryGet<String>(instanceName: 'token'), 'named-value');
      expect(bridge.tryGet<String>(), isNull);
    });

    test('tryGet propagates dependency construction errors', () {
      bridge.registerFactory<UserRepository>(
        () => throw StateError('Dependency construction failed'),
      );

      expect(
        () => bridge.tryGet<UserRepository>(),
        throwsA(isA<StateError>()),
      );
    });

    test('throws BridgeDependencyAlreadyRegisteredException when override is false', () {
      bridge.registerSingleton<AuthService>(RealAuthService());

      expect(
        () => bridge.registerSingleton<AuthService>(MockAuthService()),
        throwsA(isA<BridgeDependencyAlreadyRegisteredException>()),
      );
    });

    test('override: true replaces an existing registration and disposes the old one', () {
      var disposed = false;
      bridge.registerSingleton<String>(
        'original',
        onDispose: (_) => disposed = true,
      );

      bridge.registerSingleton<String>(
        'replacement',
        override: true,
        onDispose: (_) => disposed = false,
      );

      expect(disposed, isTrue);
      expect(bridge.get<String>(), 'replacement');
    });

    test('overrides dependency cleanly for unit testing', () {
      bridge.registerLazySingleton<AuthService>(() => RealAuthService());
      expect(bridge.get<AuthService>().login('test'), 'real_token_for_test');

      // Single-line test override
      bridge.override<AuthService>(MockAuthService());
      expect(bridge.get<AuthService>().login('test'), 'mock_token_for_test');
    });

    test('detects circular dependency and throws BridgeCircularDependencyException', () {
      bridge.registerFactory<CircularA>(() => CircularA(bridge.get<CircularB>()));
      bridge.registerFactory<CircularB>(() => CircularB(bridge.get<CircularA>()));

      expect(
        () => bridge.get<CircularA>(),
        throwsA(isA<BridgeCircularDependencyException>().having(
          (e) => e.message,
          'message',
          contains('Circular dependency detected'),
        )),
      );
    });

    test('supports named instances of the same type', () {
      bridge.registerSingleton<String>('https://dev.api.com', instanceName: 'baseUrl');
      bridge.registerSingleton<String>('secret-key-123', instanceName: 'apiKey');

      expect(bridge.isRegistered<String>(instanceName: 'baseUrl'), isTrue);
      expect(bridge.isRegistered<String>(instanceName: 'apiKey'), isTrue);
      expect(bridge.get<String>(instanceName: 'baseUrl'), 'https://dev.api.com');
      expect(bridge.get<String>(instanceName: 'apiKey'), 'secret-key-123');
    });

    test('unregister removes a dependency and triggers its onDispose hook', () {
      var disposedValue = '';
      bridge.registerSingleton<UserRepository>(
        UserRepository(),
        onDispose: (repo) => disposedValue = repo.getUser(),
      );

      expect(bridge.isRegistered<UserRepository>(), isTrue);
      bridge.unregister<UserRepository>();

      expect(bridge.isRegistered<UserRepository>(), isFalse);
      expect(bridge.tryGet<UserRepository>(), isNull);
      expect(disposedValue, 'user_42');
    });

    test('reset clears all registrations and triggers onDispose hooks', () async {
      var disposeCount = 0;
      bridge.registerSingleton<UserRepository>(
        UserRepository(),
        onDispose: (_) => disposeCount++,
      );
      bridge.registerFactory<AuthService>(() => RealAuthService());

      await bridge.reset();

      expect(disposeCount, 1);
      expect(bridge.isRegistered<UserRepository>(), isFalse);
      expect(bridge.isRegistered<AuthService>(), isFalse);
    });
  });
}
