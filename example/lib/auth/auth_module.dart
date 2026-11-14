import 'package:modular_bridge/modular_bridge.dart';
import '../core/core_module.dart';
import 'auth_repository.dart';

/// Builds an [AuthRepositoryImpl] wired with the bridge's infrastructure
/// dependencies. Shared by [AuthModule] registration and test-override
/// restoration so both paths produce identical repositories.
AuthRepository createAuthRepository(ModularBridge bridge) {
  return AuthRepositoryImpl(
    apiClient: bridge.get<ApiClient>(),
    logger: bridge.get<LoggingService>(),
    bridge: bridge,
  );
}

/// Module encapsulating authentication logic and dependencies.
final class AuthModule extends FeatureModule {
  @override
  String get name => 'AuthModule';

  @override
  List<Type> get dependencies => [CoreModule];

  @override
  void registerDependencies(ModularBridge bridge) {
    // Registers AuthRepository using dependencies resolved from CoreModule
    bridge.registerLazySingleton<AuthRepository>(
        () => createAuthRepository(bridge));
  }
}
