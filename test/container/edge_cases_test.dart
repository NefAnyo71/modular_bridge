import 'dart:async';

import 'package:test/test.dart';
import 'package:modular_bridge/modular_bridge.dart';

void main() {
  late ModularBridge bridge;

  setUp(() {
    bridge = ModularBridge.createIsolated();
  });

  tearDown(() async {
    await bridge.reset();
  });

  group('Scope stack edge cases', () {
    test('popScopesTill inclusive:false keeps the named scope active',
        () async {
      bridge.pushNewScope(scopeName: 'a');
      bridge.pushNewScope(scopeName: 'b');
      bridge.pushNewScope(scopeName: 'c');

      expect(await bridge.popScopesTill('b', inclusive: false), isTrue);
      expect(bridge.activeScopeNames, ['a', 'b']);
    });

    test('dropScope removes the named scope and everything above it', () async {
      final disposed = <String>[];
      bridge.pushNewScope(scopeName: 'a', dispose: () => disposed.add('a'));
      bridge.pushNewScope(scopeName: 'b', dispose: () => disposed.add('b'));
      bridge.pushNewScope(scopeName: 'c', dispose: () => disposed.add('c'));

      await bridge.dropScope('b');

      expect(bridge.activeScopeNames, ['a']);
      expect(disposed, containsAll(['c', 'b']));
      expect(disposed, isNot(contains('a')));
    });

    test('isScopeActive reflects push/pop/drop of named scopes', () async {
      expect(bridge.isScopeActive('a'), isFalse);

      bridge.pushNewScope(scopeName: 'a');
      expect(bridge.isScopeActive('a'), isTrue);

      bridge.pushNewScope(scopeName: 'b');
      expect(bridge.isScopeActive('b'), isTrue);

      await bridge.popScope();
      expect(bridge.isScopeActive('b'), isFalse);
      expect(bridge.isScopeActive('a'), isTrue);

      await bridge.dropScope('a');
      expect(bridge.isScopeActive('a'), isFalse);
    });

    test('isScopeActive is false for unnamed scopes', () {
      bridge.pushNewScope();
      expect(bridge.isScopeActive(''), isFalse);
      expect(bridge.activeScopeNames, hasLength(1));
    });

    test('signalReady through a scope reaches root registrations', () {
      final service = _ReadyService();
      bridge.registerSingleton<_ReadyService>(
        service,
        signalsReady: true,
      );

      bridge.pushNewScope(scopeName: 's');
      bridge.signalReady(service);

      expect(bridge.allReadySync(), isTrue);
    });
  });

  group('Reset during pending readiness', () {
    test('reset completes pending allReady waiters', () async {
      final completer = Completer<String>();
      bridge.registerAsyncSingleton<String>(() => completer.future,
          eager: true);

      var completed = false;
      unawaited(bridge
          .allReady()
          .then((_) => completed = true, onError: (_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      final resetFuture = bridge.reset();
      await Future<void>.delayed(Duration.zero);
      completer.complete('done');
      await resetFuture;
      await Future<void>.delayed(Duration.zero);
      expect(completed, isTrue);
    });
  });

  group('Dependency registration events', () {
    test('onDependencyEvents reports register and unregister', () async {
      final events = <DependencyRegistrationEvent>[];
      final sub = bridge.onDependencyEvents.listen(events.add);

      bridge.registerSingleton<String>('x');
      await bridge.unregister<String>();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events.map((e) => e.kind), [
        DependencyChangeKind.registered,
        DependencyChangeKind.unregistered,
      ]);
      expect(events.first.info.key.type, String);
    });

    test('scope registrations emit events with scope context', () async {
      final events = <DependencyRegistrationEvent>[];
      final sub = bridge.onDependencyEvents.listen(events.add);

      final scope = bridge.createScope(scopeName: 'evt');
      scope.registerSingleton<int>(1);
      await scope.dispose();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, hasLength(2));
      expect(events.first.scopeName, 'evt');
      expect(events.last.kind, DependencyChangeKind.unregistered);
    });
  });

  group('ShadowChangeHandlers', () {
    test('scope resolution notifies shadowed root instance', () async {
      final root = _ShadowableService();
      bridge.registerSingleton<_ShadowableService>(root);

      final scope = bridge.createScope(scopeName: 'shadow');
      scope.registerSingleton<_ShadowableService>(_ShadowableService());

      scope.get<_ShadowableService>();
      expect(root.shadowedBy, isNotNull);

      await scope.dispose();
      expect(root.leftShadow, isNotNull);
    });

    test('notification fires only once per shadow pair', () async {
      final root = _ShadowableService();
      bridge.registerSingleton<_ShadowableService>(root);

      final scope = bridge.createScope();
      scope.registerSingleton<_ShadowableService>(_ShadowableService());

      scope.get<_ShadowableService>();
      scope.get<_ShadowableService>();
      expect(root.shadowNotifications, 1);

      await scope.dispose();
    });
  });

  group('Environment-aware modules', () {
    test('module is skipped outside its environments allow-list', () async {
      final devConfig = BridgeConfig(environment: BridgeEnvironment.dev);
      final scoped = ModularBridge.createIsolated(config: devConfig);
      addTearDown(() async {
        await scoped.reset();
        devConfig.dispose();
      });

      await scoped.registerModule(_GatedModule());
      expect(scoped.isModuleRegistered<_GatedModule>(), isFalse);
    });

    test('module registers inside its environments allow-list', () async {
      final prodConfig = BridgeConfig(environment: BridgeEnvironment.prod);
      final scoped = ModularBridge.createIsolated(config: prodConfig);
      addTearDown(() async {
        await scoped.reset();
        prodConfig.dispose();
      });

      await scoped.registerModule(_GatedModule());
      expect(scoped.isModuleRegistered<_GatedModule>(), isTrue);
    });
  });

  group('Graphviz export', () {
    test('toDot emits a digraph with nodes and edges', () {
      bridge.registerLazySingleton<String>(() => 'dep');
      bridge.registerSingletonWithDependencies<int>(
        factoryFunc: (_) => 1,
        dependsOn: [DependencyKey(String)],
      );

      final dot = bridge.dependencyGraph().toDot();
      expect(dot, contains('digraph modular_bridge'));
      expect(dot, contains('->'));
      expect(dot, contains('String'));
    });
  });

  group('dependsOn aliases', () {
    test('dep<T> and DependencyKey.of<T> build equivalent keys', () {
      expect(dep<String>(), DependencyKey(String));
      expect(dep<String>(), DependencyKey.of<String>());
      expect(dep<String>('named'), DependencyKey(String, 'named'));
      expect(DependencyKey.of<String>('named'), DependencyKey(String, 'named'));
    });

    test('aliases work inside dependsOn orchestration', () async {
      var created = false;
      bridge.registerLazySingleton<String>(() => 'dependency');
      bridge.registerSingletonWithDependencies<int>(
        factoryFunc: (_) {
          created = true;
          return 1;
        },
        dependsOn: [dep<String>()],
      );

      expect(bridge.get<int>(), 1);
      expect(created, isTrue);
    });
  });
}

class _ReadyService {}

class _ShadowableService implements ShadowChangeHandlers {
  Object? shadowedBy;
  Object? leftShadow;
  int shadowNotifications = 0;

  @override
  void onGetShadowed(Object? shadowingInstance) {
    shadowNotifications++;
    shadowedBy = shadowingInstance;
  }

  @override
  void onLeaveShadow(Object? shadowedInstance) {
    leftShadow = shadowedInstance;
  }
}

class _GatedModule extends FeatureModule {
  @override
  String get name => 'GatedModule';

  @override
  List<BridgeEnvironment>? get environments => [BridgeEnvironment.prod];

  @override
  void registerDependencies(ModularBridge bridge) {}
}
