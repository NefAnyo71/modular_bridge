import 'dart:async';

import 'package:test/test.dart';
import 'package:modular_bridge/modular_bridge.dart';

import '../fixtures/test_fixtures.dart';

void main() {
  group('FeatureModule Lifecycle', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('registers modules and honors dependency order requirement', () async {
      final authModule = AuthTestModule();

      // Attempting to register AuthTestModule before CoreTestModule must throw
      expect(
        () => bridge.registerModule(authModule),
        throwsA(isA<BridgeModuleMissingDependencyException>().having(
          (e) => e.message,
          'message',
          contains('requires dependency module \'CoreTestModule\''),
        )),
      );

      final coreModule = CoreTestModule();
      await bridge.registerModule(coreModule);
      expect(bridge.isModuleRegistered<CoreTestModule>(), isTrue);
      expect(bridge.isRegistered<UserRepository>(), isTrue);

      // Now registering AuthTestModule succeeds
      await bridge.registerModule(authModule);
      expect(bridge.isModuleRegistered<AuthTestModule>(), isTrue);
      expect(bridge.isRegistered<AuthService>(), isTrue);
      expect(authModule.isInitialized, isTrue);
    });

    test('getModule resolves a registered module instance', () async {
      final coreModule = CoreTestModule();
      await bridge.registerModule(coreModule);

      expect(identical(bridge.getModule<CoreTestModule>(), coreModule), isTrue);
      expect(bridge.activeModuleNames, contains('CoreTestModule'));
      expect(bridge.isModuleRegistered<AuthTestModule>(), isFalse);
    });

    test('tryGetModule returns the module or null when absent', () async {
      expect(bridge.tryGetModule<CoreTestModule>(), isNull);

      final coreModule = CoreTestModule();
      await bridge.registerModule(coreModule);

      expect(
          identical(bridge.tryGetModule<CoreTestModule>(), coreModule), isTrue);
      expect(bridge.tryGetModule<AuthTestModule>(), isNull);
    });

    test('registeredDependencies exposes registered dependency keys', () async {
      await bridge.registerModule(CoreTestModule());

      final keys = bridge.registeredDependencies.toList();
      expect(keys, hasLength(1));
      expect(keys.single.type, UserRepository);
    });

    test('getModule throws BridgeModuleNotFoundException for unknown module',
        () {
      expect(
        () => bridge.getModule<AuthTestModule>(),
        throwsA(isA<BridgeModuleNotFoundException>()),
      );
    });

    test(
        'registering the same module twice throws BridgeModuleAlreadyRegisteredException',
        () async {
      final module = CoreTestModule();
      await bridge.registerModule(module);

      await expectLater(
        bridge.registerModule(CoreTestModule()),
        throwsA(isA<BridgeModuleAlreadyRegisteredException>()),
      );
    });

    test('registerModules initializes modules sequentially in list order',
        () async {
      final registrationOrder = <String>[];

      final first = _OrderTrackingModule('FirstModule', registrationOrder);
      final second = _OrderTrackingModule('SecondModule', registrationOrder);

      await bridge.registerModules([first, second]);

      expect(registrationOrder, ['FirstModule', 'SecondModule']);
      expect(bridge.isModuleRegistered<_OrderTrackingModule>(), isTrue);
    });

    test('unregisterModuleByName removes module by its name', () async {
      final coreModule = CoreTestModule();
      await bridge.registerModule(coreModule);

      expect(bridge.isModuleRegistered<CoreTestModule>(), isTrue);
      await bridge.unregisterModuleByName('CoreTestModule');

      expect(bridge.isModuleRegistered<CoreTestModule>(), isFalse);
      expect(bridge.isRegistered<UserRepository>(), isFalse);
    });

    test(
        'unregistering a module by an unknown name throws BridgeModuleNotFoundException',
        () {
      expect(
        () => bridge.unregisterModuleByName('NoSuchModule'),
        throwsA(isA<BridgeModuleNotFoundException>()),
      );
    });

    test(
        'unregistering a module required by others throws BridgeModuleInUseException',
        () async {
      await bridge.registerModules([CoreTestModule(), AuthTestModule()]);

      expect(
          bridge.moduleDependents(CoreTestModule), contains('AuthTestModule'));
      expect(bridge.moduleDependents(AuthTestModule), isEmpty);

      await expectLater(
        bridge.unregisterModule<CoreTestModule>(),
        throwsA(isA<BridgeModuleInUseException>().having(
          (e) => e.dependentModules,
          'dependentModules',
          contains('AuthTestModule'),
        )),
      );

      // Module is still registered and intact
      expect(bridge.isModuleRegistered<CoreTestModule>(), isTrue);
      expect(bridge.isRegistered<UserRepository>(), isTrue);
    });

    test('force: true unregisters a module even when dependents exist',
        () async {
      await bridge.registerModules([CoreTestModule(), AuthTestModule()]);

      await bridge.unregisterModuleByName('CoreTestModule', force: true);

      expect(bridge.isModuleRegistered<CoreTestModule>(), isFalse);
      expect(bridge.isRegistered<UserRepository>(), isFalse);
      // AuthTestModule itself remains registered (its deps are now broken,
      // which is exactly what `force` opts into).
      expect(bridge.isModuleRegistered<AuthTestModule>(), isTrue);
    });

    test('decoupled event communication works across modules', () async {
      final coreModule = CoreTestModule();
      final authModule = AuthTestModule();

      await bridge.registerModules([coreModule, authModule]);

      bridge.publish(UserLoggedOutEvent(userId: 'user_123'));
      await Future<void>.delayed(Duration.zero);

      expect(authModule.userLogoutEventReceivedCount, 1);
    });

    test(
        'unregistering a module automatically cleans its dependencies and subscriptions',
        () async {
      final coreModule = CoreTestModule();
      final authModule = AuthTestModule();
      await bridge.registerModules([coreModule, authModule]);

      expect(bridge.isRegistered<AuthService>(), isTrue);

      await bridge.unregisterModule<AuthTestModule>();

      expect(bridge.isModuleRegistered<AuthTestModule>(), isFalse);
      expect(bridge.isRegistered<AuthService>(), isFalse);
      expect(authModule.isDisposed, isTrue);

      // Core module dependencies remain intact
      expect(bridge.isRegistered<UserRepository>(), isTrue);

      // Events published now should not trigger disposed auth module listener
      bridge.publish(UserLoggedOutEvent(userId: 'user_123'));
      await Future<void>.delayed(Duration.zero);
      expect(authModule.userLogoutEventReceivedCount, 0);
    });

    test(
        'onModulesReady fires once after modules register and re-arms on empty',
        () async {
      final calls = <String>[];
      bridge.onModulesReady((b) async {
        calls.add('ready:${b.activeModuleNames.join(',')}');
      });

      await bridge.registerModules([CoreTestModule(), AuthTestModule()]);

      expect(calls, ['ready:CoreTestModule,AuthTestModule']);

      // Registering more modules does not re-fire.
      await bridge.registerModule(SimpleTestModule());
      expect(calls.length, 1);

      // Unregistering everything re-arms the hook.
      await bridge.unregisterModuleByName('SimpleTestModule');
      await bridge.unregisterModule<AuthTestModule>();
      await bridge.unregisterModuleByName('CoreTestModule');

      await bridge.registerModule(CoreTestModule());
      expect(calls.length, 2);
    });

    test(
        'onModulesReady callback registered after modules are ready fires immediately',
        () async {
      await bridge.registerModule(CoreTestModule());

      var fired = false;
      bridge.onModulesReady((_) => fired = true);
      await Future<void>.delayed(Duration.zero);

      expect(fired, isTrue);
    });

    test('modules registered inside init() do not fire onModulesReady early',
        () async {
      final readySnapshots = <String>[];
      bridge.onModulesReady(
        (b) => readySnapshots.add(b.activeModuleNames.join(',')),
      );

      await bridge.registerModule(NestedInitModule());

      // Ready fires exactly once, after BOTH modules finished initializing.
      expect(readySnapshots, ['NestedInitModule,SimpleTestModule']);
      expect(bridge.isModuleRegistered<SimpleTestModule>(), isTrue);
    });

    test('onModulesReady callback errors do not break registration', () async {
      bridge.onModulesReady((_) => throw StateError('callback failed'));

      await bridge.registerModule(CoreTestModule());
      expect(bridge.isModuleRegistered<CoreTestModule>(), isTrue);
    });

    test('rolls back module registrations when initialization fails', () async {
      final module = FailingTestModule();

      await expectLater(
        bridge.registerModule(module),
        throwsA(isA<StateError>()),
      );

      expect(bridge.isModuleRegistered<FailingTestModule>(), isFalse);
      expect(bridge.isRegistered<UserRepository>(), isFalse);
      expect(module.isDisposed, isTrue);
      expect(module.dependencyDisposed, isTrue);
      expect(bridge.eventBus.activeSubscriptionCount, 0);

      bridge.publish(UserLoggedOutEvent(userId: 'user_123'));
      await Future<void>.delayed(Duration.zero);
      expect(module.eventCount, 0);
    });

    test('supports async registerDependencies before init', () async {
      final events = <String>[];
      final module = _AsyncRegistrationModule(events);

      await bridge.registerModule(module);

      expect(events, ['dependencies', 'init']);
      expect(bridge.isRegistered<AsyncConfig>(), isTrue);
      expect((await bridge.getAsync<AsyncConfig>()).value, 'from-module');
    });

    test('rolls back async module registrations when init fails', () async {
      final module = _FailingAsyncModule();

      await expectLater(
        bridge.registerModule(module),
        throwsA(isA<StateError>()),
      );

      expect(bridge.isModuleRegistered<_FailingAsyncModule>(), isFalse);
      expect(bridge.isRegistered<AsyncConfig>(), isFalse);
      expect(module.isDisposed, isTrue);
    });

    test('parallel module registrations keep correct dependency owners',
        () async {
      final slow =
          _SlowModule('SlowModule', delay: const Duration(milliseconds: 20));
      final fast = _SlowModule('FastModule', delay: Duration.zero);

      await Future.wait([
        bridge.registerModule(slow),
        bridge.registerModule(fast),
      ]);

      // Each module's dependency must be attributed to its own owner so that
      // unregistering one never removes the other's registrations.
      await bridge.unregisterModuleByName('SlowModule');
      expect(bridge.isRegistered<AsyncConfig>(instanceName: 'SlowModule'),
          isFalse);
      expect(
          bridge.isRegistered<AsyncConfig>(instanceName: 'FastModule'), isTrue);

      await bridge.unregisterModuleByName('FastModule');
      expect(bridge.isRegistered<AsyncConfig>(instanceName: 'FastModule'),
          isFalse);
    });
  });

  group('Module health checks', () {
    late ModularBridge bridge;

    setUp(() {
      bridge = ModularBridge.createIsolated();
    });

    tearDown(() async {
      await bridge.reset();
    });

    test('checkModuleHealth reports healthy modules by default', () async {
      await bridge.registerModule(CoreTestModule());

      final results = await bridge.checkModuleHealth();

      expect(results, hasLength(1));
      expect(results.single.moduleName, 'CoreTestModule');
      expect(results.single.isHealthy, isTrue);
      expect(results.single.error, isNull);
    });

    test('returns an empty list when no modules are registered', () async {
      expect(await bridge.checkModuleHealth(), isEmpty);
    });

    test('captures false and thrown healthCheck results per module', () async {
      await bridge.registerModules([
        _HealthModule(moduleName: 'UnhealthyModule', healthy: false),
        _HealthModule(
            moduleName: 'ThrowingModule', error: StateError('probe failed')),
        _HealthModule(moduleName: 'AsyncModule'),
      ]);

      final results = await bridge.checkModuleHealth();
      final byName = {for (final r in results) r.moduleName: r};

      expect(byName['UnhealthyModule']!.isHealthy, isFalse);
      expect(byName['UnhealthyModule']!.error, isNull);
      expect(byName['ThrowingModule']!.isHealthy, isFalse);
      expect(byName['ThrowingModule']!.error, isA<StateError>());
      expect(byName['AsyncModule']!.isHealthy, isTrue);
      expect(
        byName['AsyncModule']!.moduleName,
        'AsyncModule',
      );
    });

    test('healthCheck receives the bridge instance', () async {
      final module = _HealthModule(moduleName: 'ProbeModule');
      await bridge.registerModule(module);

      await bridge.checkModuleHealth();
      expect(module.seenBridge, same(bridge));
    });

    test('throws StateError on a disposed bridge', () async {
      await bridge.dispose();
      expect(
        () => bridge.checkModuleHealth(),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'registerModule(checkHealth: true) runs healthCheck and stays quiet '
        'for healthy modules', () async {
      final module = _HealthModule(moduleName: 'AutoHealthy');
      final reports = <BridgeErrorReport>[];
      final previous = bridgeErrorReporter;
      bridgeErrorReporter = _CollectingReporter(reports);
      addTearDown(() => bridgeErrorReporter = previous);

      await bridge.registerModule(module, checkHealth: true);

      expect(module.healthCheckCalls, 1);
      expect(reports, isEmpty);
    });

    test(
        'registerModule(checkHealth: true) reports unhealthy and throwing '
        'modules without failing registration', () async {
      final reports = <BridgeErrorReport>[];
      final previous = bridgeErrorReporter;
      bridgeErrorReporter = _CollectingReporter(reports);
      addTearDown(() => bridgeErrorReporter = previous);

      final unhealthy =
          _HealthModule(moduleName: 'AutoUnhealthy', healthy: false);
      final throwing = _HealthModule(
          moduleName: 'AutoThrowing', error: StateError('probe failed'));

      await bridge.registerModule(unhealthy, checkHealth: true);
      await bridge.registerModule(throwing, checkHealth: true);

      // Both modules registered successfully despite failing health checks.
      expect(bridge.isModuleRegistered<_HealthModule>(), isTrue);
      expect(reports, hasLength(2));
      expect(
        reports.map((r) => r.context),
        containsAll([
          contains('AutoUnhealthy'),
          contains('AutoThrowing'),
        ]),
      );
    });

    test('registerModule without checkHealth does not run healthCheck',
        () async {
      final module = _HealthModule(moduleName: 'LazyHealth');
      await bridge.registerModule(module);

      expect(module.healthCheckCalls, 0);
    });
  });
}

class _CollectingReporter implements BridgeErrorReporter {
  _CollectingReporter(this.reports);

  final List<BridgeErrorReport> reports;

  @override
  void report(BridgeErrorReport report) {
    reports.add(report);
  }
}

class _AsyncRegistrationModule extends FeatureModule {
  _AsyncRegistrationModule(this.events);

  final List<String> events;

  @override
  String get name => 'AsyncRegistrationModule';

  @override
  Future<void> registerDependencies(ModularBridge bridge) async {
    await Future<void>.delayed(Duration.zero);
    events.add('dependencies');
    bridge.registerAsyncSingleton<AsyncConfig>(
      () async => AsyncConfig('from-module'),
    );
  }

  @override
  void init(ModularBridge bridge) {
    events.add('init');
  }
}

class _FailingAsyncModule extends FeatureModule {
  @override
  String get name => '_FailingAsyncModule';

  @override
  Future<void> registerDependencies(ModularBridge bridge) async {
    await Future<void>.delayed(Duration.zero);
    bridge.registerAsyncSingleton<AsyncConfig>(() async => AsyncConfig('x'));
  }

  @override
  void init(ModularBridge bridge) {
    throw StateError('async init failed');
  }
}

class _SlowModule extends FeatureModule {
  _SlowModule(this.moduleName, {required this.delay});

  final String moduleName;
  final Duration delay;

  @override
  String get name => moduleName;

  @override
  Future<void> registerDependencies(ModularBridge bridge) async {
    await Future<void>.delayed(delay);
    bridge.registerAsyncSingleton<AsyncConfig>(
      () async => AsyncConfig(moduleName),
      instanceName: moduleName,
    );
  }
}

class _OrderTrackingModule extends FeatureModule {
  _OrderTrackingModule(this.moduleName, this.log);

  final String moduleName;
  final List<String> log;

  @override
  String get name => moduleName;

  @override
  void registerDependencies(ModularBridge bridge) {}

  @override
  void init(ModularBridge bridge) {
    log.add(moduleName);
  }
}

class _HealthModule extends FeatureModule {
  _HealthModule({required this.moduleName, this.healthy = true, this.error});

  final String moduleName;

  final bool healthy;
  final Object? error;
  ModularBridge? seenBridge;
  int healthCheckCalls = 0;

  @override
  String get name => moduleName;

  @override
  void registerDependencies(ModularBridge bridge) {}

  @override
  FutureOr<bool> healthCheck(ModularBridge bridge) async {
    healthCheckCalls++;
    seenBridge = bridge;
    await Future<void>.delayed(Duration.zero);
    if (error != null) throw error!;
    return healthy;
  }
}
