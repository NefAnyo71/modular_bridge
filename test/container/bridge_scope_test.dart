import 'dart:async';

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

    group('Async lifecycles', () {
      test('registerAsyncSingleton caches and retries failures', () async {
        final scope = bridge.createScope();
        var calls = 0;
        scope.registerAsyncSingleton<AsyncConfig>(() async {
          calls++;
          if (calls == 1) throw StateError('temporary');
          return AsyncConfig('ok_$calls');
        });

        await expectLater(scope.getAsync<AsyncConfig>(), throwsStateError);
        final result = await scope.getAsync<AsyncConfig>();
        expect(result.value, 'ok_2');
        expect(calls, 2);

        // Cached after success.
        expect((await scope.getAsync<AsyncConfig>()).value, 'ok_2');
        expect(calls, 2);
      });

      test(
          'get on a scoped async dependency throws BridgeAsyncDependencyException',
          () {
        final scope = bridge.createScope();
        scope.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('x'));

        expect(() => scope.get<AsyncConfig>(),
            throwsA(isA<BridgeAsyncDependencyException>()));
      });

      test('registerFactoryAsync produces fresh instances per call', () async {
        final scope = bridge.createScope();
        var calls = 0;
        scope.registerFactoryAsync<AsyncConfig>(() async {
          calls++;
          return AsyncConfig('call_$calls');
        });

        expect((await scope.getAsync<AsyncConfig>()).value, 'call_1');
        expect((await scope.getAsync<AsyncConfig>()).value, 'call_2');
        expect(calls, 2);
      });

      test('tryGetAsync resolves scoped and parent async dependencies',
          () async {
        bridge.registerAsyncSingleton<AsyncConfig>(
            () async => AsyncConfig('global'));
        final scope = bridge.createScope();
        scope.registerAsyncSingleton<String>(() async => 'scoped');

        expect(await scope.tryGetAsync<String>(), 'scoped');
        expect(await scope.tryGetAsync<double>(), isNull);
        expect((await scope.tryGetAsync<AsyncConfig>())?.value, 'global');
      });

      test('detects circular async dependencies inside a scope', () async {
        final scope = bridge.createScope();
        scope.registerAsyncSingleton<AsyncCircularA>(
          () async => AsyncCircularA(await scope.getAsync<AsyncCircularB>()),
        );
        scope.registerAsyncSingleton<AsyncCircularB>(
          () async => AsyncCircularB(await scope.getAsync<AsyncCircularA>()),
        );

        await expectLater(
          scope.getAsync<AsyncCircularA>(),
          throwsA(isA<BridgeCircularDependencyException>()),
        );
      });

      test('scope getAsync falls back to parent bridge async dependencies',
          () async {
        bridge.registerAsyncSingleton<AsyncConfig>(
            () async => AsyncConfig('from-bridge'));
        final scope = bridge.createScope();

        expect((await scope.getAsync<AsyncConfig>()).value, 'from-bridge');
        expect(bridge.isRegistered<AsyncConfig>(), isTrue);
      });

      test('dispose waits for in-flight async resolution and async onDispose',
          () async {
        final completer = Completer<AsyncConfig>();
        var disposed = false;
        final scope = bridge.createScope();
        scope.registerAsyncSingleton<AsyncConfig>(
          () => completer.future,
          onDispose: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            disposed = true;
          },
        );

        final pending = scope.getAsync<AsyncConfig>();
        await Future<void>.delayed(Duration.zero);
        final disposeFuture = scope.dispose();
        completer.complete(AsyncConfig('late'));

        await expectLater(pending, throwsStateError);
        await disposeFuture;
        expect(disposed, isTrue);
        expect(scope.isDisposed, isTrue);
      });
    });

    group('Scope hierarchy', () {
      test('child scopes resolve through parent then bridge', () {
        bridge.registerSingleton<String>('bridge-value');
        final parent = bridge.createScope();
        parent.registerSingleton<int>(7);
        final child = parent.createChildScope();

        child.registerSingleton<double>(1.5);

        expect(child.get<double>(), 1.5);
        expect(child.get<int>(), 7);
        expect(child.get<String>(), 'bridge-value');
        expect(parent.isRegistered<double>(), isFalse);
        expect(bridge.isRegistered<int>(), isFalse);
      });

      test('child scope shadows parent registrations', () {
        final parent = bridge.createScope();
        parent.registerSingleton<String>('parent');
        final child = parent.createChildScope();
        child.registerSingleton<String>('child');

        expect(child.get<String>(), 'child');
        expect(parent.get<String>(), 'parent');
      });

      test('disposing a parent disposes its children first', () async {
        var childDisposed = false;
        var parentDisposed = false;
        final parent = bridge.createScope();
        final child = parent.createChildScope();

        parent.registerSingleton<String>('p',
            onDispose: (_) => parentDisposed = true);
        child.registerSingleton<String>('c',
            onDispose: (_) => childDisposed = true);

        await parent.dispose();

        expect(child.isDisposed, isTrue);
        expect(childDisposed, isTrue);
        expect(parentDisposed, isTrue);
      });

      test('unregister only affects the owning scope', () async {
        final parent = bridge.createScope();
        final child = parent.createChildScope();
        parent.registerSingleton<int>(1);
        child.registerSingleton<int>(2);

        await child.unregister<int>();

        expect(child.get<int>(), 1); // falls back to parent
        expect(parent.get<int>(), 1);
      });

      test('createChildScope on a disposed scope throws', () async {
        final scope = bridge.createScope();
        await scope.dispose();

        expect(() => scope.createChildScope(), throwsStateError);
      });
    });

    group('createScopeAsync', () {
      test('runs init, seals the scope and returns it', () async {
        final scope = await bridge.createScopeAsync((s) async {
          await Future<void>.delayed(Duration.zero);
          s.registerSingleton<String>('configured');
        });

        expect(scope.get<String>(), 'configured');
        expect(
          () => scope.registerSingleton<int>(1),
          throwsStateError,
        );
      });

      test('disposes the scope when init fails', () async {
        var disposed = false;
        await expectLater(
          bridge.createScopeAsync((s) async {
            s.registerSingleton<String>('x', onDispose: (_) => disposed = true);
            throw StateError('init failed');
          }),
          throwsStateError,
        );

        expect(disposed, isTrue);
      });
    });
  });
}
