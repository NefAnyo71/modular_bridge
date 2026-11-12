import 'package:modular_bridge/modular_bridge.dart';
import '../core/core_module.dart';
import 'auth_repository.dart';

/// Module encapsulating authentication logic and dependencies.
final class AuthModule extends FeatureModule {
  @override
  String get name => 'AuthModule';

  @override
  List<Type> get dependencies => [CoreModule];

  @override
  void registerDependencies(ModularBridge bridge) {
    // Registers AuthRepository using dependencies resolved from CoreModule
    bridge.registerLazySingleton<AuthRepository>(() {
      final apiClient = bridge.get<ApiClient>();
      final logger = bridge.get<LoggingService>();
      return AuthRepositoryImpl(
        apiClient: apiClient,
        logger: logger,
        bridge: bridge,
      );
    });
  }
}

