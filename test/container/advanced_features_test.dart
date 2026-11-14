import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';

import '../fixtures/test_fixtures.dart';

void main() {
  late ModularBridge bridge;

  setUp(() {
    bridge = ModularBridge.createIsolated();
  });

  tearDown(() async {
    await bridge.reset();
  });

  group('Parameterized factories', () {
    test('registerFactoryParam resolves with runtime params', () {
      bridge.registerFactoryParam<String, int, String>(
        (count, suffix) => '$count$suffix',
      );

      expect(
          bridge.getParam<String, int, String>(param1: 3, param2: 'x'), '3x');
      expect(
          bridge.getParam<String, int, String>(param1: 7, param2: 'y'), '7y');
    });

    test('registerCachedFactoryParam caches per parameter pair', () {
      var calls = 0;
      bridge.registerCachedFactoryParam<String, int, int>(
        (a, b) {
          calls++;
          return '$a+$b';
        },
      );

      final first = bridge.getParam<String, int, int>(param1: 1, param2: 2);
      final second = bridge.getParam<String, int, int>(param1: 1, param2: 2);
      final third = bridge.getParam<String, int, int>(param1: 2, param2: 2);

      expect(identical(first, second), isTrue);
      expect(calls, 2);
      expect(third, '2+2');
    });

    test('getParam on a non-param registration throws StateError', () {
      bridge.registerFactory<String>(() => 'plain');
      expect(
        () => bridge.getParam<String, int, int>(param1: 1, param2: 2),
        throwsStateError,
      );
    });

    test('get on a param registration throws a helpful StateError', () {
      bridge.registerFactoryParam<String, int, int>((a, b) => '$a$b');
      expect(() => bridge.get<String>(), throwsStateError);
    });

    test('async param factories resolve via getParamAsync', () async {
      bridge.registerFactoryParamAsync<String, int, int>(
        (a, b) async => '${a * b}',
        instanceName: 'mul',
      );
      bridge.registerCachedFactoryParamAsync<String, String, int>(
        (s, n) async => '$s$n',
        instanceName: 'cat',
      );

      expect(
        await bridge.getParamAsync<String, int, int>(
            param1: 6, param2: 7, instanceName: 'mul'),
        '42',
      );
      final a = await bridge.getParamAsync<String, String, int>(
          param1: 'v', param2: 1, instanceName: 'cat');
      final b = await bridge.getParamAsync<String, String, int>(
          param1: 'v', param2: 1, instanceName: 'cat');
      expect(identical(a, b), isTrue);
    });

    test('param factories work inside pushed scopes', () async {
      bridge.pushNewScope(scopeName: 'p');
      bridge.registerFactoryParam<String, int, int>((a, b) => '${a + b}');

      expect(
        bridge.getParam<String, int, int>(param1: 2, param2: 3),
        '5',
      );
      await bridge.popScope();
    });
  });

  group('getAll', () {
    test('resolves all named registrations of a type', () {
      bridge.registerSingleton<String>('one', instanceName: 'first');
      bridge.registerSingleton<String>('two', instanceName: 'second');
      bridge.registerSingleton<int>(1);

      expect(
        bridge.getAll<String>().toSet(),
        {'one', 'two'},
      );
    });

    test('getAllAsync resolves async registrations', () async {
      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('a'),
          instanceName: 'a');
      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('b'),
          instanceName: 'b');

      final configs = await bridge.getAllAsync<AsyncConfig>();
      expect(configs.map((c) => c.value).toSet(), {'a', 'b'});
    });

    test('scope getAll prefers nearest registration per key', () async {
      bridge.registerSingleton<String>('root', instanceName: 'shared');
      bridge.registerSingleton<String>('scoped', instanceName: 'local');
      bridge.registerSingleton<String>('root-only', instanceName: 'other');

      bridge.pushNewScope(scopeName: 's');
      bridge.registerSingleton<String>('scoped', instanceName: 'shared');

      final values = bridge.getAll<String>().toSet();
      expect(values, {'scoped', 'root-only'});
      await bridge.popScope();
    });
  });

  group('Dependency graph', () {
    test('reports edges and no cycles for acyclic dependsOn', () {
      bridge.registerLazySingleton<String>(() => 'dep');
      bridge.registerSingletonWithDependencies<int>(
        factoryFunc: (_) => 1,
        dependsOn: [DependencyKey(String)],
      );

      final graph = bridge.dependencyGraph();
      expect(graph.hasCycles, isFalse);
      expect(graph.edges, hasLength(1));
      expect(graph.edges.single.to, DependencyKey(String));
      expect(graph.nodes, hasLength(2));
    });

    test('detects dependsOn cycles', () {
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

      final graph = bridge.dependencyGraph();
      expect(graph.hasCycles, isTrue);
      expect(graph.cycles, isNotEmpty);
    });
  });

  group('Readiness timeout details', () {
    test('allReady timeout throws BridgeWaitingTimeOutException', () async {
      final completer = Completer<AsyncConfig>();
      bridge.registerAsyncSingleton<AsyncConfig>(() => completer.future,
          eager: true);
      bridge.registerSingleton<String>('ready', signalsReady: true);
      bridge.signalReady(bridge.get<String>());

      await expectLater(
        bridge.allReady(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<BridgeWaitingTimeOutException>().having(
          (e) => e.pending,
          'pending',
          contains(DependencyKey(AsyncConfig).toString()),
        )),
      );
      completer.complete(AsyncConfig('done'));
      await bridge.allReady();
    });

    test('isReady timeout reports the pending dependency', () async {
      final completer = Completer<AsyncConfig>();
      bridge.registerAsyncSingleton<AsyncConfig>(() => completer.future);

      await expectLater(
        bridge.isReady<AsyncConfig>(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<BridgeWaitingTimeOutException>()),
      );
      completer.complete(AsyncConfig('done'));
    });
  });

  group('Module init ordering', () {
    test('registerModules initializes dependencies first', () async {
      final order = <String>[];
      _ChildOrderedModule.order = order;
      _ParentOrderedModule.order = order;

      await bridge.registerModules([
        _ChildOrderedModule(),
        _ParentOrderedModule(),
      ]);

      expect(order, ['parent', 'child']);
    });

    test('registerModules detects dependency cycles', () {
      expect(
        () => bridge.registerModules([_CycleModuleA(), _CycleModuleB()]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Test helpers', () {
    test('assertRegistered and assertAllReadySync', () async {
      bridge.registerSingleton<String>('x');
      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('c'),
          eager: true);

      bridge.assertRegistered<String>();
      await bridge.allReady();
      bridge.assertAllReadySync();
      expect(bridge.pendingReadinessKeys, isEmpty);

      expect(() => bridge.assertRegistered<int>(), throwsStateError);
    });
  });
}

class _ParentOrderedModule extends FeatureModule {
  static List<String> order = [];

  @override
  String get name => 'Ordered_parent';

  @override
  void registerDependencies(ModularBridge bridge) {}

  @override
  void init(ModularBridge bridge) {
    order.add('parent');
  }
}

class _ChildOrderedModule extends FeatureModule {
  static List<String> order = [];

  @override
  String get name => 'Ordered_child';

  @override
  List<Type> get dependencies => [_ParentOrderedModule];

  @override
  void registerDependencies(ModularBridge bridge) {}

  @override
  void init(ModularBridge bridge) {
    order.add('child');
  }
}

class _CycleModuleA extends FeatureModule {
  @override
  String get name => 'Cycle_a';

  @override
  List<Type> get dependencies => [_CycleModuleB];

  @override
  void registerDependencies(ModularBridge bridge) {}
}

class _CycleModuleB extends FeatureModule {
  @override
  String get name => 'Cycle_b';

  @override
  List<Type> get dependencies => [_CycleModuleA];

  @override
  void registerDependencies(ModularBridge bridge) {}
}
