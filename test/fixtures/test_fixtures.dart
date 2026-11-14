/// Shared test fixtures: dummy services, events, circular dependencies
/// and [FeatureModule] implementations used across the test suite.
library;

import 'package:modular_bridge/modular_bridge.dart';

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

class AsyncConfig {
  AsyncConfig(this.value);
  final String value;
}

class AsyncCircularA {
  AsyncCircularA(this.b);
  final AsyncCircularB b;
}

class AsyncCircularB {
  AsyncCircularB(this.a);
  final AsyncCircularA a;
}

class MixedAsyncA {
  MixedAsyncA(this.b);
  final MixedSyncB b;
}

class MixedSyncB {
  MixedSyncB(this.pendingAsyncA);
  final Future<Object?> pendingAsyncA;
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
    await super.dispose(bridge);
  }
}

class SimpleTestModule extends FeatureModule {
  @override
  String get name => 'SimpleTestModule';

  @override
  void registerDependencies(ModularBridge bridge) {}
}

class NestedInitModule extends FeatureModule {
  @override
  String get name => 'NestedInitModule';

  @override
  void registerDependencies(ModularBridge bridge) {}

  @override
  Future<void> init(ModularBridge bridge) async {
    await bridge.registerModule(SimpleTestModule());
  }
}

class FailingTestModule extends FeatureModule {
  @override
  String get name => 'FailingTestModule';

  bool dependencyDisposed = false;
  int eventCount = 0;

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerSingleton<UserRepository>(
      UserRepository(),
      onDispose: (_) => dependencyDisposed = true,
    );
  }

  @override
  void init(ModularBridge bridge) {
    subscribe<UserLoggedOutEvent>(bridge, (_) => eventCount++);
    throw StateError('Module initialization failed');
  }

  @override
  Future<void> dispose(ModularBridge bridge) async {
    await super.dispose(bridge);
  }
}
