import 'dart:async';

import 'package:test/test.dart';
import 'package:modular_bridge/modular_bridge.dart';

import '../fixtures/test_fixtures.dart';

void main() {
  group('Scope stack (get_it parity)', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('pushNewScope routes registrations and resolution through the scope',
        () async {
      var disposed = false;
      bridge.pushNewScope(
        scopeName: 'request',
        dispose: () => disposed = true,
      );

      bridge.registerSingleton<String>('scoped');
      bridge.registerLazySingleton<int>(() => 42);

      expect(bridge.get<String>(), 'scoped');
      expect(bridge.get<int>(), 42);
      expect(bridge.currentScope?.scopeName, 'request');

      await bridge.popScope();

      expect(disposed, isTrue);
      expect(bridge.currentScope, isNull);
      expect(bridge.isRegistered<String>(), isFalse);
      expect(() => bridge.get<String>(),
          throwsA(isA<BridgeDependencyNotFoundException>()));
    });

    test('scoped registrations shadow root registrations', () async {
      bridge.registerSingleton<String>('root');

      bridge.pushNewScope(scopeName: 'inner');
      bridge.registerSingleton<String>('inner-value');

      expect(bridge.get<String>(), 'inner-value');
      await bridge.popScope();
      expect(bridge.get<String>(), 'root');
    });

    test('pushNewScopeAsync awaits init and pushNewScope isFinal seals',
        () async {
      final events = <String>[];
      await bridge.pushNewScopeAsync(
        scopeName: 'async-scope',
        init: (b) async {
          await Future<void>.delayed(Duration.zero);
          b.registerSingleton<String>('async-value');
          events.add('init-done');
        },
      );

      expect(events, ['init-done']);
      expect(bridge.get<String>(), 'async-value');

      bridge.pushNewScope(scopeName: 'final', isFinal: true);
      expect(
        () => bridge.registerSingleton<int>(1),
        throwsStateError,
      );
      await bridge.popScope();
      await bridge.popScope();
    });

    test('popScopesTill and dropScope remove named scopes', () async {
      bridge.pushNewScope(scopeName: 'a');
      bridge.pushNewScope(scopeName: 'b');
      bridge.pushNewScope(scopeName: 'c');

      expect(await bridge.popScopesTill('b'), isTrue);
      expect(bridge.activeScopeNames, ['a']);

      await bridge.pushNewScopeAsync(scopeName: 'd');
      await bridge.dropScope('a');
      expect(bridge.activeScopeNames, isEmpty);
      expect(() => bridge.dropScope('missing'),
          throwsA(isA<BridgeScopeNotFoundException>()));
    });

    test('onScopeChanged fires on push and pop', () async {
      final events = <bool>[];
      bridge.onScopeChanged = events.add;

      bridge.pushNewScope(scopeName: 's1');
      await bridge.popScope();

      expect(events, [true, false]);
    });

    test('resetScope clears current scope registrations without popping',
        () async {
      bridge.registerSingleton<String>('root');
      bridge.pushNewScope(scopeName: 'req');
      bridge.registerSingleton<int>(7);

      await bridge.resetScope();

      expect(bridge.isRegistered<int>(), isFalse);
      expect(bridge.get<String>(), 'root');
      expect(bridge.currentScope?.scopeName, 'req');
      await bridge.popScope();
    });

    test('bridge.unregister removes scope-local registrations', () async {
      bridge.pushNewScope(scopeName: 'req');
      bridge.registerSingleton<String>('local');

      await bridge.unregister<String>();

      expect(() => bridge.get<String>(),
          throwsA(isA<BridgeDependencyNotFoundException>()));
      await bridge.popScope();
    });
  });

  group('Lazy singleton reset', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('resetLazySingleton recreates the instance and runs dispose',
        () async {
      var created = 0;
      var disposed = 0;
      bridge.registerLazySingleton<UserRepository>(
        () {
          created++;
          return UserRepository();
        },
        onDispose: (_) => disposed++,
      );

      final first = bridge.get<UserRepository>();
      await bridge.resetLazySingleton<UserRepository>();
      final second = bridge.get<UserRepository>();

      expect(created, 2);
      expect(disposed, 1);
      expect(identical(first, second), isFalse);
    });

    test('resetLazySingleton with disposeHooks false drops the instance',
        () async {
      var disposed = 0;
      bridge.registerLazySingleton<String>(
        () => 'value',
        onDispose: (_) => disposed++,
      );

      expect(bridge.get<String>(), 'value');
      await bridge.resetLazySingleton<String>(disposeHooks: false);
      expect(bridge.get<String>(), 'value');
      expect(disposed, 0);
    });

    test('resetLazySingletons resets all instantiated lazy singletons',
        () async {
      var a = 0;
      var b = 0;
      bridge.registerLazySingleton<String>(() {
        a++;
        return 'a$a';
      });
      bridge.registerLazySingleton<int>(() {
        b++;
        return b;
      });
      bridge.registerFactory<double>(() => 0.5);

      bridge.get<String>();
      bridge.get<int>();
      await bridge.resetLazySingletons();

      expect(bridge.get<String>(), 'a2');
      expect(bridge.get<int>(), 2);
    });

    test('resetLazySingleton throws for non-lazy lifecycles', () async {
      bridge.registerFactory<String>(() => 'x');
      await expectLater(
        bridge.resetLazySingleton<String>(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Startup orchestration (signalsReady / dependsOn)', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('signalsReady blocks allReady until signalReady(instance)', () async {
      final service = _ManualReadyService();
      bridge.registerSingleton<_ManualReadyService>(
        service,
        signalsReady: true,
      );

      expect(bridge.allReadySync(), isFalse);
      var allReadyCompleted = false;
      unawaited(bridge.allReady().then((_) => allReadyCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(allReadyCompleted, isFalse);

      bridge.signalReady(service);
      await bridge.allReady();
      expect(allReadyCompleted, isTrue);
      expect(bridge.allReadySync(), isTrue);
    });

    test('WillSignalReady marker implies signalsReady', () async {
      final service = _MarkerReadyService();
      bridge.registerSingleton<_MarkerReadyService>(service);

      expect(bridge.allReadySync(), isFalse);
      bridge.signalReady(service);
      expect(bridge.allReadySync(), isTrue);
    });

    test('signalReady(null) completes all pending manual signals', () async {
      final a = _ManualReadyService();
      final b = _ManualReadyService();
      bridge.registerSingleton<_ManualReadyService>(a,
          instanceName: 'a', signalsReady: true);
      bridge.registerSingleton<_ManualReadyService>(b,
          instanceName: 'b', signalsReady: true);

      bridge.signalReady();
      expect(bridge.allReadySync(), isTrue);
    });

    test('signalReady rejects instances that are not marked', () {
      final service = _ManualReadyService();
      bridge.registerSingleton<_ManualReadyService>(service);

      expect(() => bridge.signalReady(service), throwsArgumentError);
    });

    test('registerSingletonWithDependencies waits for dependsOn', () async {
      final order = <String>[];
      bridge.registerLazySingleton<String>(() {
        order.add('dep');
        return 'dep-value';
      });
      bridge.registerSingletonWithDependencies<int>(
        factoryFunc: (b) {
          order.add('main');
          return b.get<String>().length;
        },
        dependsOn: [DependencyKey(String)],
      );

      await bridge.allReady();
      expect(order, ['dep', 'main']);
      expect(bridge.get<int>(), 9);
    });

    test('registerSingletonWithDependenciesAsync waits for dependsOn',
        () async {
      final order = <String>[];
      bridge.registerLazySingleton<String>(() {
        order.add('dep');
        return 'dep-value';
      });
      bridge.registerSingletonWithDependenciesAsync<int>(
        factoryFunc: (b) async {
          order.add('main');
          await Future<void>.delayed(Duration.zero);
          return (await b.getAsync<String>()).length;
        },
        dependsOn: [DependencyKey(String)],
      );

      await bridge.allReady();
      expect(order, ['dep', 'main']);
      expect(await bridge.getAsync<int>(), 9);
      // Async lifecycles reject synchronous resolution.
      expect(() => bridge.get<int>(),
          throwsA(isA<BridgeAsyncDependencyException>()));
    });

    test('dependsOn circular orchestration is detected', () async {
      bridge.registerLazySingleton<String>(
        () => 'a',
        instanceName: 'a',
        dependsOn: [DependencyKey(int, 'b')],
      );
      bridge.registerLazySingleton<int>(
        () => 1,
        instanceName: 'b',
        dependsOn: [DependencyKey(String, 'a')],
      );

      await expectLater(
        bridge.getAsync<String>(instanceName: 'a'),
        throwsA(isA<BridgeCircularDependencyException>()),
      );
    });
  });

  group('Async registration aliases', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('registerSingletonAsync starts eagerly and joins allReady', () async {
      var calls = 0;
      bridge.registerSingletonAsync<AsyncConfig>(() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return AsyncConfig('eager');
      });

      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      await bridge.allReady();
      expect((await bridge.getAsync<AsyncConfig>()).value, 'eager');
    });

    test('registerLazySingletonAsync stays lazy', () async {
      var calls = 0;
      bridge.registerLazySingletonAsync<AsyncConfig>(() async {
        calls++;
        return AsyncConfig('lazy');
      });

      await bridge.allReady();
      expect(calls, 0);
      await bridge.getAsync<AsyncConfig>();
      expect(calls, 1);
    });
  });

  group('Config-bound dependencies', () {
    late ModularBridge bridge;
    late BridgeConfig config;

    setUp(() {
      config = BridgeConfig(
        environment: BridgeEnvironment.dev,
        commonValues: {'feature.enabled': false},
        environmentValues: {
          BridgeEnvironment.prod: {'feature.enabled': true},
        },
      );
      bridge = ModularBridge.createIsolated(config: config);
    });

    tearDown(() async {
      await bridge.reset();
      config.dispose();
    });

    test('registerConfigBinding re-decodes on environment switch', () async {
      bridge.registerConfigBinding<bool>(
        configKey: 'feature.enabled',
        decoder: (v) => v as bool,
      );

      expect(bridge.get<bool>(), isFalse);
      config.switchEnvironment(BridgeEnvironment.prod);
      await Future<void>.delayed(Duration.zero);

      expect(bridge.get<bool>(), isTrue);
    });

    test('config binding disposes the previous decoded instance', () async {
      var disposed = 0;
      bridge.registerConfigBinding<String>(
        configKey: 'feature.enabled',
        decoder: (v) => 'enabled:$v',
        onDispose: (_) => disposed++,
      );

      expect(bridge.get<String>(), 'enabled:false');
      config.set('feature.enabled', true);
      await Future<void>.delayed(Duration.zero);

      expect(bridge.get<String>(), 'enabled:true');
      expect(disposed, 1);
    });

    test('config binding owned by a disposed scope is dropped silently',
        () async {
      final reports = <BridgeErrorReport>[];
      final previous = bridgeErrorReporter;
      bridgeErrorReporter = _RecordingReporter(reports);
      addTearDown(() => bridgeErrorReporter = previous);

      final scope = bridge.pushNewScope(scopeName: 'cfg');
      bridge.registerConfigBinding<bool>(
        configKey: 'feature.enabled',
        decoder: (v) => v as bool,
      );
      await bridge.popScope();

      config.switchEnvironment(BridgeEnvironment.prod);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(reports, isEmpty);
      expect(scope.isDisposed, isTrue);
    });
  });

  group('Disposable & reassignment', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('instances implementing Disposable are disposed automatically',
        () async {
      var disposed = 0;
      bridge.registerSingleton<_DisposableService>(_DisposableService(
        disposeCallback: () {
          disposed++;
        },
      ));

      await bridge.unregister<_DisposableService>();
      expect(disposed, 1);
    });

    test('explicit onDispose wins over Disposable.onDispose', () async {
      var hookDisposed = 0;
      var autoDisposed = 0;
      bridge.registerSingleton<_DisposableService>(
        _DisposableService(disposeCallback: () {
          autoDisposed++;
        }),
        onDispose: (_) => hookDisposed++,
      );

      await bridge.reset();
      expect(hookDisposed, 1);
      expect(autoDisposed, 0);
    });

    test('allowReassignment replaces registrations without override', () {
      bridge.allowReassignment = true;
      bridge.registerSingleton<String>('first');
      bridge.registerSingleton<String>('second');

      expect(bridge.get<String>(), 'second');
    });

    test('allowReassignment also applies inside pushed scopes', () async {
      bridge.allowReassignment = true;
      bridge.pushNewScope(scopeName: 's');
      bridge.registerSingleton<String>('a');
      bridge.registerSingleton<String>('b');

      expect(bridge.get<String>(), 'b');
      await bridge.popScope();
    });

    test('currentScopeName reflects the active scope', () async {
      expect(bridge.currentScopeName, isNull);
      bridge.pushNewScope(scopeName: 'named');
      expect(bridge.currentScopeName, 'named');
      await bridge.popScope();
      expect(bridge.currentScopeName, isNull);
    });

    test('unregister falls back to root when scope does not own the key',
        () async {
      var disposed = 0;
      bridge.registerSingleton<String>('root', onDispose: (_) => disposed++);
      bridge.pushNewScope(scopeName: 's');

      await bridge.unregister<String>();
      expect(disposed, 1);
      expect(bridge.isRegistered<String>(), isFalse);

      await bridge.popScope();
    });
  });

  group('Diagnostics', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('diagnosticsReport aggregates registrations, scopes and modules',
        () async {
      bridge.registerSingleton<String>('root');
      bridge.pushNewScope(scopeName: 'req');
      bridge.registerLazySingleton<int>(() => 1);
      await bridge.registerModule(_DiagnosticsModule());

      final report = bridge.diagnosticsReport();

      expect(report.isHealthy, isTrue);
      expect(report.moduleNames, contains('DiagnosticsModule'));
      expect(report.activeScopeNames, contains('req'));
      expect(report.scopeStack, ['req']);
      expect(
        report.registrations.map((d) => d.key.type),
        containsAll([String, int, AsyncConfig]),
      );
      expect(
        report.registrations.firstWhere((d) => d.key.type == int).scopeName,
        'req',
      );
      expect(
        report.registrations
            .firstWhere((d) => d.key.type == AsyncConfig)
            .ownerModuleName,
        'DiagnosticsModule',
      );

      await bridge.popScope();
    });
  });

  group('Reset disposeInstances (get_it parity)', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('reset(disposeInstances: false) drops hooks and registrations',
        () async {
      var disposed = 0;
      bridge.registerSingleton<String>(
        'x',
        onDispose: (_) => disposed++,
      );
      bridge.registerLazySingleton<int>(() => 1);
      bridge.get<int>();

      await bridge.reset(disposeInstances: false);

      expect(disposed, 0);
      expect(bridge.isRegistered<String>(), isFalse);
      expect(bridge.isRegistered<int>(), isFalse);
    });

    test('reset() defaults to disposing instances', () async {
      var disposed = 0;
      bridge.registerSingleton<String>(
        'x',
        onDispose: (_) => disposed++,
      );

      await bridge.reset();

      expect(disposed, 1);
    });

    test('disposeInstances flag propagates into live scopes', () async {
      var disposed = 0;
      final scope = bridge.createScope(scopeName: 's');
      scope.registerSingleton<String>(
        'scoped',
        onDispose: (_) => disposed++,
      );

      await bridge.reset(disposeInstances: false);

      expect(disposed, 0);
      expect(scope.isDisposed, isTrue);
    });
  });
}

class _ManualReadyService {}

class _MarkerReadyService implements WillSignalReady {}

class _DisposableService implements Disposable {
  _DisposableService({required this.disposeCallback});

  final FutureOr<void> Function() disposeCallback;

  @override
  FutureOr<void> onDispose() => disposeCallback();
}

class _DiagnosticsModule extends FeatureModule {
  @override
  String get name => 'DiagnosticsModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('m'));
  }
}

class _RecordingReporter implements BridgeErrorReporter {
  _RecordingReporter(this.reports);

  final List<BridgeErrorReport> reports;

  @override
  void report(BridgeErrorReport report) => reports.add(report);
}
