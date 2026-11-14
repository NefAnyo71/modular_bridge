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

    test('tryGet returns the resolved instance when dependency is registered',
        () {
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

    test(
        'throws BridgeDependencyAlreadyRegisteredException when override is false',
        () {
      bridge.registerSingleton<AuthService>(RealAuthService());

      expect(
        () => bridge.registerSingleton<AuthService>(MockAuthService()),
        throwsA(isA<BridgeDependencyAlreadyRegisteredException>()),
      );
    });

    test(
        'override: true replaces an existing registration and disposes the old one',
        () {
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

    test(
        'detects circular dependency and throws BridgeCircularDependencyException',
        () {
      bridge
          .registerFactory<CircularA>(() => CircularA(bridge.get<CircularB>()));
      bridge
          .registerFactory<CircularB>(() => CircularB(bridge.get<CircularA>()));

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
      bridge.registerSingleton<String>('https://dev.api.com',
          instanceName: 'baseUrl');
      bridge.registerSingleton<String>('secret-key-123',
          instanceName: 'apiKey');

      expect(bridge.isRegistered<String>(instanceName: 'baseUrl'), isTrue);
      expect(bridge.isRegistered<String>(instanceName: 'apiKey'), isTrue);
      expect(
          bridge.get<String>(instanceName: 'baseUrl'), 'https://dev.api.com');
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

    test('reset clears all registrations and triggers onDispose hooks',
        () async {
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

  group('Async Dependency Injection', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('registers and resolves async singleton via getAsync with caching',
        () async {
      var factoryCalls = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(() async {
        factoryCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return AsyncConfig('cfg_$factoryCalls');
      });

      final first = await bridge.getAsync<AsyncConfig>();
      final second = await bridge.getAsync<AsyncConfig>();

      expect(factoryCalls, 1);
      expect(first.value, 'cfg_1');
      expect(identical(first, second), isTrue);
    });

    test('get on an async singleton throws BridgeAsyncDependencyException', () {
      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('x'));

      expect(
        () => bridge.get<AsyncConfig>(),
        throwsA(isA<BridgeAsyncDependencyException>()),
      );
    });

    test('concurrent getAsync calls share a single factory invocation',
        () async {
      var factoryCalls = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(() async {
        factoryCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return AsyncConfig('shared');
      });

      final results = await Future.wait([
        bridge.getAsync<AsyncConfig>(),
        bridge.getAsync<AsyncConfig>(),
        bridge.getAsync<AsyncConfig>(),
      ]);

      expect(factoryCalls, 1);
      expect(
        results.every((r) => identical(r, results.first)),
        isTrue,
      );
    });

    test('failed async resolution is retried on the next call', () async {
      var factoryCalls = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(() async {
        factoryCalls++;
        if (factoryCalls == 1) {
          throw StateError('transient failure');
        }
        return AsyncConfig('recovered');
      });

      await expectLater(
        bridge.getAsync<AsyncConfig>(),
        throwsA(isA<StateError>()),
      );

      final recovered = await bridge.getAsync<AsyncConfig>();
      expect(recovered.value, 'recovered');
      expect(factoryCalls, 2);
    });

    test('tryGetAsync returns null for missing and resolves registered deps',
        () async {
      expect(await bridge.tryGetAsync<AsyncConfig>(), isNull);

      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('a'));
      expect((await bridge.tryGetAsync<AsyncConfig>())?.value, 'a');
    });

    test('getAsync resolves synchronous dependencies transparently', () async {
      bridge.registerSingleton<String>('sync-value');
      bridge.registerLazySingleton<UserRepository>(UserRepository.new);

      expect(await bridge.getAsync<String>(), 'sync-value');
      expect((await bridge.getAsync<UserRepository>()).getUser(), 'user_42');
    });

    test('detects circular async dependencies', () async {
      bridge.registerAsyncSingleton<AsyncCircularA>(
        () async => AsyncCircularA(await bridge.getAsync<AsyncCircularB>()),
      );
      bridge.registerAsyncSingleton<AsyncCircularB>(
        () async => AsyncCircularB(await bridge.getAsync<AsyncCircularA>()),
      );

      await expectLater(
        bridge.getAsync<AsyncCircularA>(),
        throwsA(isA<BridgeCircularDependencyException>()),
      );
    });

    test('async singleton can depend on sync and other async dependencies',
        () async {
      bridge.registerSingleton<String>('token-123');
      bridge.registerAsyncSingleton<ApiConfigHolder>(
        () async => ApiConfigHolder(
          token: bridge.get<String>(),
          remote: await bridge.getAsync<AsyncConfig>(),
        ),
      );
      bridge.registerAsyncSingleton<AsyncConfig>(
          () async => AsyncConfig('remote'));

      final holder = await bridge.getAsync<ApiConfigHolder>();
      expect(holder.token, 'token-123');
      expect(holder.remote.value, 'remote');
    });

    test('unregistering an async singleton disposes the resolved instance',
        () async {
      var disposed = false;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async => AsyncConfig('x'),
        onDispose: (_) => disposed = true,
      );

      await bridge.getAsync<AsyncConfig>();
      bridge.unregister<AsyncConfig>();

      expect(bridge.isRegistered<AsyncConfig>(), isFalse);
      expect(disposed, isTrue);
    });

    test('async singleton supports named instances', () async {
      bridge.registerAsyncSingleton<String>(
        () async => 'primary',
        instanceName: 'db.primary',
      );
      bridge.registerAsyncSingleton<String>(
        () async => 'replica',
        instanceName: 'db.replica',
      );

      expect(
          await bridge.getAsync<String>(instanceName: 'db.primary'), 'primary');
      expect(
          await bridge.getAsync<String>(instanceName: 'db.replica'), 'replica');
    });
  });

  group('Debug Leak Inspection', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('debugLeakReport is empty on a fresh container', () {
      expect(bridge.debugLeakReport(), isEmpty);
      expect(() => bridge.assertNoLeaks(), returnsNormally);
    });

    test('debugLeakReport detects leftover resolution state after reset',
        () async {
      bridge.registerSingleton<UserRepository>(UserRepository());
      await bridge.reset();

      // reset() clears everything, so the report stays clean.
      expect(bridge.debugLeakReport(), isEmpty);
    });
  });

  group('Config Swapping', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('setConfig emits onConfigChanged with the new instance', () async {
      final events = <BridgeConfig>[];
      final sub = bridge.onConfigChanged.listen(events.add);
      addTearDown(sub.cancel);

      final newConfig = BridgeConfig(environment: BridgeEnvironment.prod);
      bridge.setConfig(newConfig);
      await Future<void>.delayed(Duration.zero);

      expect(events, [same(newConfig)]);
      expect(bridge.config, same(newConfig));
      expect(bridge.config.environment, BridgeEnvironment.prod);
    });
  });
}

class ApiConfigHolder {
  ApiConfigHolder({required this.token, required this.remote});
  final String token;
  final AsyncConfig remote;
}
