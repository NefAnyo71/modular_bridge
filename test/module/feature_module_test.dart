import 'package:flutter_test/flutter_test.dart';
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
  });
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
