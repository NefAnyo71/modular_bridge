import 'package:modular_bridge/modular_bridge.dart';
import '../auth/auth_events.dart';
import '../core/core_module.dart';
import 'home_controller.dart';

/// Module managing Home screen features.
///
/// Demonstrates decoupled communication: it reacts to [UserLoggedInEvent]
/// and [UserLoggedOutEvent] without any direct dependency on the internal
/// implementation of `AuthModule`.
final class HomeModule extends FeatureModule {
  @override
  String get name => 'HomeModule';

  @override
  List<Type> get dependencies => [CoreModule];

  @override
  void registerDependencies(ModularBridge bridge) {
    // Registers HomeController as a lazy singleton
    bridge.registerLazySingleton<HomeController>(
      () => HomeController(),
      onDispose: (controller) => controller.dispose(),
    );
  }

  @override
  void init(ModularBridge bridge) {
    final controller = bridge.get<HomeController>();
    final logger = bridge.get<LoggingService>();

    // Listen to UserLoggedInEvent in a completely decoupled fashion
    subscribe<UserLoggedInEvent>(bridge, (event) {
      logger.log('[HomeModule] Received UserLoggedInEvent: ${event.email}');
      controller.loadFeedForUser(event.email);
    });

    // Listen to UserLoggedOutEvent to clean state
    subscribe<UserLoggedOutEvent>(bridge, (event) {
      logger
          .log('[HomeModule] Received UserLoggedOutEvent. Clearing home feed.');
      controller.clearFeed();
    });
  }
}
