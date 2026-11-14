import 'package:modular_bridge/modular_bridge.dart';
import '../auth/auth_events.dart';
import '../core/core_module.dart';
import 'cart_service.dart';

/// Module managing shopping cart state and checkout workflows.
///
/// Demonstrates cross-module decoupling:
/// Automatically clears its state when [UserLoggedOutEvent] is broadcast,
/// with ZERO imports or dependencies on `AuthModule`'s internal classes.
final class CartModule extends FeatureModule {
  @override
  String get name => 'CartModule';

  @override
  List<Type> get dependencies => [CoreModule];

  @override
  void registerDependencies(ModularBridge bridge) {
    bridge.registerLazySingleton<CartService>(
      () => CartService(bridge),
      // dep<T>() is a shorthand alias for DependencyKey(T) — the factory
      // only runs after LoggingService has been resolved.
      dependsOn: [dep<LoggingService>()],
      onDispose: (service) => service.dispose(),
    );
  }

  @override
  void init(ModularBridge bridge) {
    final cartService = bridge.get<CartService>();
    final logger = bridge.get<LoggingService>();

    // Listen to UserLoggedOutEvent with auto-disposal lifecycle
    subscribe<UserLoggedOutEvent>(bridge, (event) {
      logger.log(
          '[CartModule] User logged out (${event.userId}). Auto-clearing cart items.');
      cartService.clear(reason: 'User session terminated');
    });
  }
}
