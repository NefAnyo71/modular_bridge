import 'package:modular_bridge/modular_bridge.dart';

import '../core/core_module.dart';
import 'auth_service.dart';

/// Builds an [AuthService] wired with the bridge's infrastructure.
///
/// `AuthService` receives a [Lazy<UserProfileService>] — the profile service
/// depends back on `AuthService`, so this is what keeps the pair acyclic.
AuthService createAuthService(ModularBridge bridge) {
  return AuthService(
    bridge: bridge,
    logger: bridge.get<LoggingService>(),
    profile: bridge.lazy<UserProfileService>(),
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
    bridge.registerLazySingleton<AuthService>(
      () => createAuthService(bridge),
      onDispose: (service) => service.dispose(),
    );

    // Eagerly depends on AuthService at construction, but AuthService only
    // holds a Lazy back-reference — the cycle is broken.
    bridge.registerLazySingleton<UserProfileService>(
      () => UserProfileService(bridge.get<AuthService>()),
    );
  }

  @override
  Future<bool> healthCheck(ModularBridge bridge) async {
    // Verifies the infrastructure this module depends on is reachable:
    // CoreModule's ApiClient must exist and answer a health probe.
    final apiClient = bridge.tryGet<ApiClient>();
    if (apiClient == null) return false;
    final response = await apiClient.get('/health');
    return response.isNotEmpty;
  }
}
