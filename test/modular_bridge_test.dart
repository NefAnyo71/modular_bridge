import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modular_bridge/modular_bridge.dart';

// -----------------------------------------------------------------------------
// TEST FIXTURES & DUMMY SERVICES
// -----------------------------------------------------------------------------

abstract class AuthService {
  String login(String email);
}

class RealAuthService implements AuthService {
  @override
  String login(String email) => 'real_token_for_$email';
}

class MockAuthService implements AuthService {
  @override
  String login(String email) => 'mock_token_for_$email';
}

class UserRepository {
  int callCount = 0;
  String getUser() {
    callCount++;
    return 'user_42';
  }
}

class CircularA {
  CircularA(this.b);
  final CircularB b;
}

class CircularB {
  CircularB(this.a);
  final CircularA a;
}

// Events
final class UserLoggedInEvent extends BridgeEvent {
  UserLoggedInEvent({required this.userId, required this.email});
  final String userId;
  final String email;
}

final class UserLoggedOutEvent extends BridgeEvent {
  UserLoggedOutEvent({required this.userId});
  final String userId;
}

final class OrderPlacedEvent extends BridgeEvent {
  OrderPlacedEvent({required this.orderId});
  final String orderId;
}

// Modules
class CoreTestModule extends FeatureModule {
  @override
  String get name => 'CoreTestModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerSingleton<UserRepository>(UserRepository());
  }
}

class AuthTestModule extends FeatureModule {
  @override
  String get name => 'AuthTestModule';

  @override
  List<Type> get dependencies => [CoreTestModule];

  bool isInitialized = false;
  bool isDisposed = false;
  int userLogoutEventReceivedCount = 0;

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<AuthService>(() => RealAuthService());
  }

  @override
  void init(ModularBridge bridge) {
    isInitialized = true;
    subscribe<UserLoggedOutEvent>(bridge, (event) {
      userLogoutEventReceivedCount++;
    });
  }

  @override
  void dispose(ModularBridge bridge) async {
    isDisposed = true;
    await super.dispose(bridge);
  }
}

void main() {
  group('1. Dependency Injection & Lifecycle Tests', () {
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

    test('tryGet returns null when dependency is missing', () {
      expect(bridge.tryGet<AuthService>(), isNull);
    });

    test('throws BridgeDependencyAlreadyRegisteredException when override is false', () {
      bridge.registerSingleton<AuthService>(RealAuthService());

      expect(
        () => bridge.registerSingleton<AuthService>(MockAuthService()),
        throwsA(isA<BridgeDependencyAlreadyRegisteredException>()),
      );
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

      expect(bridge.get<String>(instanceName: 'baseUrl'), 'https://dev.api.com');
      expect(bridge.get<String>(instanceName: 'apiKey'), 'secret-key-123');
    });
  });

  group('2. Type-Safe BridgeConfig Tests', () {
    late BridgeConfig config;

    setUp(() {
      config = BridgeConfig(
        environment: BridgeEnvironment.dev,
        commonValues: {
          'appName': 'ModularBridgeApp',
          'supportEmail': 'support@example.com',
          'port': 8080,
          'timeout': const Duration(seconds: 30),
          'isDebug': true,
          'apiRatio': 1.5,
          'serverUri': Uri.parse('https://example.com/api'),
        },
        environmentValues: {
          BridgeEnvironment.dev: {
            'apiUrl': 'https://dev.api.com',
            'featureBiometrics': false,
            'maxRetries': 5,
          },
          BridgeEnvironment.staging: {
            'apiUrl': 'https://staging.api.com',
            'featureBiometrics': true,
            'maxRetries': 3,
          },
          BridgeEnvironment.prod: {
            'apiUrl': 'https://api.com',
            'featureBiometrics': true,
            'maxRetries': 1,
          },
        },
      );
    });

    tearDown(() {
      config.dispose();
    });

    test('reads strongly typed values correctly', () {
      expect(config.getString('appName'), 'ModularBridgeApp');
      expect(config.getString('apiUrl'), 'https://dev.api.com');
      expect(config.getInt('port'), 8080);
      expect(config.getInt('maxRetries'), 5);
      expect(config.getBool('featureBiometrics'), isFalse);
      expect(config.getDouble('apiRatio'), 1.5);
      expect(config.getDuration('timeout'), const Duration(seconds: 30));
      expect(config.getUri('serverUri'), Uri.parse('https://example.com/api'));
    });

    test('throws BridgeConfigKeyNotFoundException when key is missing and no default provided', () {
      expect(
        () => config.get<String>('nonExistentKey'),
        throwsA(isA<BridgeConfigKeyNotFoundException>()),
      );
      expect(
        () => config.getString('nonExistentKey'),
        throwsA(isA<BridgeConfigKeyNotFoundException>()),
      );
    });

    test('returns defaultValue when key is missing', () {
      expect(config.getString('nonExistentKey', defaultValue: 'fallback'), 'fallback');
      expect(config.getInt('missingInt', defaultValue: 42), 42);
      expect(config.getBool('missingBool', defaultValue: true), isTrue);
      expect(config.getDouble('missingDouble', defaultValue: 3.14), 3.14);
      expect(
        config.getDuration('missingDuration', defaultValue: const Duration(seconds: 5)),
        const Duration(seconds: 5),
      );
      expect(
        config.getUri('missingUri', defaultValue: Uri.parse('https://fallback.com')),
        Uri.parse('https://fallback.com'),
      );
    });

    test('throws BridgeConfigTypeMismatchException when type does not match', () {
      expect(
        () => config.getInt('appName'), // appName is String 'ModularBridgeApp'
        throwsA(isA<BridgeConfigTypeMismatchException>().having(
          (e) => e.message,
          'message',
          contains('expected type \'int\''),
        )),
      );
    });

    test('hot-switches environment at runtime and notifies listeners', () async {
      expect(config.environment, BridgeEnvironment.dev);
      expect(config.getString('apiUrl'), 'https://dev.api.com');
      expect(config.getInt('maxRetries'), 5);

      final envChanges = <BridgeEnvironment>[];
      final subscription = config.onEnvironmentChanged.listen(envChanges.add);

      config.switchEnvironment(BridgeEnvironment.prod);

      // Wait a microtask for broadcast
      await Future<void>.delayed(Duration.zero);

      expect(config.environment, BridgeEnvironment.prod);
      expect(config.getString('apiUrl'), 'https://api.com');
      expect(config.getInt('maxRetries'), 1);
      expect(envChanges, [BridgeEnvironment.prod]);

      await subscription.cancel();
    });

    test('parses BridgeEnvironment from string correctly', () {
      expect(BridgeEnvironment.fromString('dev'), BridgeEnvironment.dev);
      expect(BridgeEnvironment.fromString('DEVELOPMENT'), BridgeEnvironment.dev);
      expect(BridgeEnvironment.fromString('staging'), BridgeEnvironment.staging);
      expect(BridgeEnvironment.fromString('prod'), BridgeEnvironment.prod);
      expect(
        () => BridgeEnvironment.fromString('invalid_env'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('3. Decoupled Event Bus Tests', () {
    late BridgeEventBus eventBus;

    setUp(() {
      eventBus = BridgeEventBus();
    });

    tearDown(() async {
      await eventBus.dispose();
    });

    test('publishes and receives strongly typed events', () async {
      final receivedLogins = <UserLoggedInEvent>[];
      final receivedLogouts = <UserLoggedOutEvent>[];

      eventBus.subscribe<UserLoggedInEvent>((e) => receivedLogins.add(e));
      eventBus.subscribe<UserLoggedOutEvent>((e) => receivedLogouts.add(e));

      eventBus.publish(UserLoggedInEvent(userId: 'u1', email: 'u1@test.com'));
      eventBus.publish(UserLoggedOutEvent(userId: 'u1'));
      eventBus.publish(OrderPlacedEvent(orderId: 'ord_999'));

      await Future<void>.delayed(Duration.zero);

      expect(receivedLogins.length, 1);
      expect(receivedLogins.first.userId, 'u1');
      expect(receivedLogouts.length, 1);
      expect(receivedLogouts.first.userId, 'u1');
    });

    test('canceling a BridgeSubscription stops event delivery', () async {
      var callCount = 0;
      final sub = eventBus.subscribe<UserLoggedInEvent>((_) => callCount++);

      eventBus.publish(UserLoggedInEvent(userId: '1', email: 'a@b.com'));
      await Future<void>.delayed(Duration.zero);
      expect(callCount, 1);

      await sub.cancel();
      expect(sub.isCanceled, isTrue);

      eventBus.publish(UserLoggedInEvent(userId: '2', email: 'c@d.com'));
      await Future<void>.delayed(Duration.zero);
      expect(callCount, 1); // Unchanged
    });

    test('cancels all subscriptions for a specific ownerId', () async {
      var mod1Count = 0;
      var mod2Count = 0;

      eventBus.subscribe<UserLoggedOutEvent>((_) => mod1Count++, ownerId: 'Module1');
      eventBus.subscribe<UserLoggedOutEvent>((_) => mod2Count++, ownerId: 'Module2');

      eventBus.publish(UserLoggedOutEvent(userId: '1'));
      await Future<void>.delayed(Duration.zero);
      expect(mod1Count, 1);
      expect(mod2Count, 1);

      // Cancel only Module1
      await eventBus.cancelSubscriptionsForOwner('Module1');

      eventBus.publish(UserLoggedOutEvent(userId: '2'));
      await Future<void>.delayed(Duration.zero);
      expect(mod1Count, 1); // Not called
      expect(mod2Count, 2); // Still called
    });
  });

  group('4. FeatureModule Lifecycle & Inter-Module Communication Tests', () {
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

    test('decoupled event communication works across modules', () async {
      final coreModule = CoreTestModule();
      final authModule = AuthTestModule();

      await bridge.registerModules([coreModule, authModule]);

      bridge.publish(UserLoggedOutEvent(userId: 'user_123'));
      await Future<void>.delayed(Duration.zero);

      expect(authModule.userLogoutEventReceivedCount, 1);
    });

    test('unregistering a module automatically cleans its dependencies and subscriptions', () async {
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
  });

  group('5. Flutter Widget Integration Tests', () {
    testWidgets('ModularBridgeScope and BuildContext extensions resolve dependencies', (tester) async {
      final testBridge = ModularBridge.createIsolated();
      testBridge.registerSingleton<String>('Hello ModularBridge');

      late String resolvedValue;

      await tester.pumpWidget(
        ModularBridgeScope(
          bridge: testBridge,
          child: Builder(
            builder: (context) {
              resolvedValue = context.get<String>();
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolvedValue, 'Hello ModularBridge');
    });

    testWidgets('ModularBridgeProvider rebuilds subtree on environment hot-switch', (tester) async {
      final config = BridgeConfig(
        environment: BridgeEnvironment.dev,
        environmentValues: {
          BridgeEnvironment.dev: {'envLabel': 'Development Mode'},
          BridgeEnvironment.prod: {'envLabel': 'Production Mode'},
        },
      );
      final testBridge = ModularBridge.createIsolated(config: config);

      await tester.pumpWidget(
        ModularBridgeProvider(
          bridge: testBridge,
          child: Builder(
            builder: (context) {
              final label = context.config.getString('envLabel');
              return Directionality(
                textDirection: TextDirection.ltr,
                child: Text(label),
              );
            },
          ),
        ),
      );

      expect(find.text('Development Mode'), findsOneWidget);

      // Hot-switch to prod
      testBridge.config.switchEnvironment(BridgeEnvironment.prod);
      await tester.pump();

      expect(find.text('Production Mode'), findsOneWidget);
    });
  });
}
