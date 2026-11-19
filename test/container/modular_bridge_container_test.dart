import 'dart:async';

import 'package:test/test.dart';
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

    test('unregister returns true when a registration was removed', () async {
      bridge.registerSingleton<String>('x');

      expect(await bridge.unregister<String>(), isTrue);
      expect(bridge.isRegistered<String>(), isFalse);
      expect(await bridge.unregister<String>(), isFalse);
      await expectLater(
        bridge.unregister<String>(throwOnMissing: true),
        throwsA(isA<BridgeDependencyNotFoundException>()),
      );
    });

    test('overrideAsync and overrideFactory replace registrations', () async {
      bridge.registerSingleton<String>('real');
      bridge.overrideFactory<String>(() => 'fake');
      expect(bridge.get<String>(), 'fake');

      bridge.registerAsyncSingleton<int>(() async => 1, instanceName: 'n');
      bridge.overrideAsync<int>(() async => 2, instanceName: 'n');
      expect(await bridge.getAsync<int>(instanceName: 'n'), 2);
    });

    test('failed with-dependencies resolution surfaces via allReady', () async {
      bridge.registerAsyncSingleton<AsyncConfig>(
        () => Future<AsyncConfig>.error(StateError('boom')),
        instanceName: 'bad',
      );
      bridge.registerSingletonWithDependencies<String>(
        factoryFunc: (_) => 'x',
        dependsOn: [DependencyKey(AsyncConfig, 'bad')],
      );

      // The orchestration error must surface through allReady — and must
      // not leak as an unhandled async error from the cleanup chain.
      await expectLater(bridge.allReady(), throwsA(anything));
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

    test('registerFactoryAsync produces a new instance per getAsync', () async {
      var calls = 0;
      bridge.registerFactoryAsync<AsyncConfig>(() async {
        calls++;
        return AsyncConfig('call_$calls');
      });

      final first = await bridge.getAsync<AsyncConfig>();
      final second = await bridge.getAsync<AsyncConfig>();

      expect(calls, 2);
      expect(first.value, 'call_1');
      expect(second.value, 'call_2');
      expect(identical(first, second), isFalse);
    });

    test('get on an async factory throws BridgeAsyncDependencyException', () {
      bridge.registerFactoryAsync<AsyncConfig>(() async => AsyncConfig('x'));

      expect(
        () => bridge.get<AsyncConfig>(),
        throwsA(isA<BridgeAsyncDependencyException>()),
      );
    });

    test('mixed sync/async circular chains are detected', () async {
      bridge.registerAsyncSingleton<MixedAsyncA>(
        () async => MixedAsyncA(await bridge.getAsync<MixedSyncB>()),
      );
      // The sync factory resolves the async dependency that is already on
      // the resolution chain: the inner getAsync must surface a circular
      // dependency error instead of deadlocking. The error is captured as a
      // value so it does not surface as an unhandled async error.
      bridge.registerFactory<MixedSyncB>(
        () => MixedSyncB(
          bridge.getAsync<MixedAsyncA>().then<Object?>(
                (value) => value,
                onError: (Object error) => error,
              ),
        ),
      );

      final resolved = await bridge.getAsync<MixedAsyncA>();
      final outcome = await resolved.b.pendingAsyncA;
      expect(outcome, isA<BridgeCircularDependencyException>());
    });
  });

  group('Async Readiness (get_it parity)', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('eager async singletons start resolving at registration', () async {
      var calls = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return AsyncConfig('eager');
        },
        eager: true,
      );

      // Resolution started without an explicit getAsync call.
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      final resolved = await bridge.getAsync<AsyncConfig>();
      expect(resolved.value, 'eager');
    });

    test('allReady completes immediately when nothing is pending', () async {
      await expectLater(bridge.allReady(), completes);
      expect(bridge.allReadySync(), isTrue);
    });

    test('allReady waits for eager async singletons only', () async {
      var eagerDone = false;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          eagerDone = true;
          return AsyncConfig('ready');
        },
        eager: true,
      );
      // Lazy async singletons must not block allReady.
      bridge.registerAsyncSingleton<String>(() async => 'lazy');

      await bridge.allReady();
      expect(eagerDone, isTrue);
      expect(bridge.allReadySync(), isTrue);
    });

    test('allReady ignores pending async factories', () async {
      bridge.registerFactoryAsync<AsyncConfig>(
        () => Future<AsyncConfig>.delayed(
          const Duration(milliseconds: 50),
          () => AsyncConfig('slow'),
        ),
      );

      await expectLater(bridge.allReady(), completes);
    });

    test('allReady times out listing pending dependencies', () async {
      final completer = Completer<AsyncConfig>();
      bridge.registerAsyncSingleton<AsyncConfig>(
        () => completer.future,
        eager: true,
      );

      await Future<void>.delayed(Duration.zero);
      await expectLater(
        bridge.allReady(timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()),
      );

      // Let the pending resolution finish so tearDown's reset() does not
      // wait on it forever.
      completer.complete(AsyncConfig('late'));
      await bridge.allReady();
    });

    test('isReady resolves async singletons and completes for sync deps',
        () async {
      bridge.registerSingleton<String>('sync');
      await expectLater(bridge.isReady<String>(), completes);

      bridge.registerAsyncSingleton<AsyncConfig>(
        () async => AsyncConfig('ready'),
      );
      await expectLater(bridge.isReady<AsyncConfig>(), completes);
      expect(bridge.isReadySync<AsyncConfig>(), isTrue);
    });

    test('isReadySync reports pending eager resolutions', () async {
      final completer = Completer<AsyncConfig>();
      bridge.registerAsyncSingleton<AsyncConfig>(
        () => completer.future,
        eager: true,
      );

      await Future<void>.delayed(Duration.zero);
      expect(bridge.isReadySync<AsyncConfig>(), isFalse);

      completer.complete(AsyncConfig('done'));
      await bridge.allReady();
      expect(bridge.isReadySync<AsyncConfig>(), isTrue);
    });

    test('unregister waits for async disposal hooks', () async {
      var disposed = false;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () async => AsyncConfig('x'),
        onDispose: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          disposed = true;
        },
      );

      await bridge.getAsync<AsyncConfig>();
      await bridge.unregister<AsyncConfig>();

      expect(disposed, isTrue);
      expect(bridge.isRegistered<AsyncConfig>(), isFalse);
    });

    test('unregister with throwOnMissing raises for absent dependencies',
        () async {
      await expectLater(
        bridge.unregister<AuthService>(throwOnMissing: true),
        throwsA(isA<BridgeDependencyNotFoundException>()),
      );
      // Default stays silent for backwards compatibility.
      await expectLater(bridge.unregister<AuthService>(), completes);
    });

    test('failed async resolution is retried after failure', () async {
      var calls = 0;
      bridge.registerAsyncSingleton<AsyncConfig>(() async {
        calls++;
        if (calls == 1) throw StateError('boom');
        return AsyncConfig('recovered');
      });

      await expectLater(bridge.getAsync<AsyncConfig>(), throwsStateError);
      expect((await bridge.getAsync<AsyncConfig>()).value, 'recovered');
      expect(calls, 2);
    });

    test('dispose during in-flight async resolution disposes the result',
        () async {
      final completer = Completer<AsyncConfig>();
      var disposed = false;
      bridge.registerAsyncSingleton<AsyncConfig>(
        () => completer.future,
        onDispose: (_) => disposed = true,
      );

      final pending = bridge.getAsync<AsyncConfig>();
      await Future<void>.delayed(Duration.zero);
      final resetFuture = bridge.reset();
      completer.complete(AsyncConfig('late'));

      await expectLater(pending, throwsStateError);
      await resetFuture;
      expect(disposed, isTrue);
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
