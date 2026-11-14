import 'package:test/test.dart';
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

  group('Resolution metrics', () {
    test('records resolutions, cache hits and durations', () async {
      var factoryCalls = 0;
      bridge.registerLazySingleton<String>(() {
        factoryCalls++;
        return 'v$factoryCalls';
      });
      bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('c'));

      bridge.get<String>();
      bridge.get<String>(); // cache hit
      await bridge.getAsync<AsyncConfig>();
      await bridge.getAsync<AsyncConfig>(); // shared/cached hit

      final metrics = bridge.metrics;
      expect(metrics.totalResolutions, greaterThanOrEqualTo(4));
      expect(metrics.totalCacheHits, greaterThanOrEqualTo(2));
      expect(metrics.cacheHitRatio, greaterThan(0));

      final entry = metrics.entries[DependencyKey(String).toString()];
      expect(entry, isNotNull);
      expect(entry!.resolutions, 2);
      expect(entry.cacheHits, 1);
      expect(entry.averageMicros, greaterThanOrEqualTo(0));

      final snapshot = metrics.snapshot();
      expect(snapshot['totalResolutions'], metrics.totalResolutions);
      expect(snapshot['entries'], isA<Map>());
    });

    test('diagnosticsReport includes metrics snapshot', () {
      bridge.registerSingleton<String>('x');
      bridge.get<String>();

      final report = bridge.diagnosticsReport();
      expect(report.metrics['totalResolutions'], greaterThanOrEqualTo(1));
    });

    test('resetMetrics clears counters', () {
      bridge.registerSingleton<String>('x');
      bridge.get<String>();
      bridge.resetMetrics();

      expect(bridge.metrics.totalResolutions, 0);
    });
  });

  group('warmup', () {
    test('resolves all singleton-style registrations eagerly', () async {
      var lazyCreated = false;
      var asyncCreated = false;
      bridge.registerLazySingleton<String>(() {
        lazyCreated = true;
        return 'lazy';
      });
      bridge.registerAsyncSingleton<AsyncConfig>(() async {
        asyncCreated = true;
        return AsyncConfig('warm');
      });
      bridge.registerFactory<int>(() => 1); // transient: skipped

      await bridge.warmup();

      expect(lazyCreated, isTrue);
      expect(asyncCreated, isTrue);
      expect(bridge.get<String>(), 'lazy');
      expect(bridge.allReadySync(), isTrue);
    });

    test('warmup propagates resolution errors', () async {
      bridge.registerLazySingleton<String>(() => throw StateError('boom'));

      await expectLater(bridge.warmup(), throwsStateError);
    });

    test('warmup resolves scope registrations when included', () async {
      var scoped = false;
      final scope = bridge.createScope(scopeName: 'warm');
      scope.registerLazySingleton<String>(() {
        scoped = true;
        return 'scoped';
      });

      await bridge.warmup();
      expect(scoped, isTrue);
      await scope.dispose();
    });

    test('warmup ownerModule filter only resolves that module', () async {
      var moduleDep = false;
      var rootDep = false;
      await bridge.registerModule(_WarmModule(() => moduleDep = true));
      bridge.registerLazySingleton<int>(() {
        rootDep = true;
        return 1;
      });

      await bridge.warmup(ownerModule: 'WarmModule');
      expect(moduleDep, isTrue);
      expect(rootDep, isFalse);

      await bridge.warmup();
      expect(rootDep, isTrue);
    });
  });

  group('Module metrics', () {
    test('moduleEntries aggregates resolutions per module', () async {
      await bridge.registerModule(CoreTestModule());
      bridge.get<UserRepository>();
      bridge.get<UserRepository>(); // cache hit still counts

      final entry = bridge.metrics.moduleEntries['CoreTestModule'];
      expect(entry, isNotNull);
      // CoreTestModule uses registerSingleton, so every get is a cache hit.
      expect(entry!.resolutions, 2);
      expect(entry.cacheHits, 2);

      final snapshot = bridge.metrics.snapshot();
      expect(snapshot['byModule'], isA<Map>());
      expect((snapshot['byModule'] as Map)['CoreTestModule'], isA<Map>());
    });
  });

  group('Event bus extras', () {
    test('lastEvent returns the most recent matching event', () {
      bridge.publish(_TestEvent('first'));
      bridge.publish(_TestEvent('second'));
      bridge.publish(_OtherEvent());

      expect(bridge.lastEvent<_TestEvent>()?.value, 'second');
      expect(bridge.lastEvent<_OtherEvent>(), isNotNull);
      expect(bridge.lastEvent<_TestEvent2>(), isNull);
    });

    test('history replays recent events then continues live', () async {
      bridge.publish(_TestEvent('h1'));
      bridge.publish(_TestEvent('h2'));

      final received = <String>[];
      final sub = bridge.history<_TestEvent>().listen(
            (e) => received.add(e.value),
          );
      await Future<void>.delayed(Duration.zero);
      bridge.publish(_TestEvent('live'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(received, ['h1', 'h2', 'live']);
    });

    test('clearReplayHistory empties history and latest', () async {
      bridge.publish(_TestEvent('x'));
      bridge.eventBus.clearReplayHistory();

      expect(bridge.lastEvent<_TestEvent>(), isNull);
      final received = <String>[];
      final sub =
          bridge.history<_TestEvent>().listen((e) => received.add(e.value));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(received, isEmpty);
    });
  });

  group('DevTools', () {
    test('enableDevTools registers service extensions without throwing', () {
      expect(() => bridge.enableDevTools(), returnsNormally);
      // Second call is a no-op thanks to the process-wide guard.
      expect(() => bridge.enableDevTools(), returnsNormally);
    });
  });
}

class _TestEvent extends BridgeEvent {
  _TestEvent(this.value);
  final String value;
}

class _OtherEvent extends BridgeEvent {}

class _TestEvent2 extends BridgeEvent {}

class _WarmModule extends FeatureModule {
  _WarmModule(this.onResolve);

  final void Function() onResolve;

  @override
  String get name => 'WarmModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<String>(() {
      onResolve();
      return 'warm';
    });
  }
}
