import 'package:modular_bridge/modular_bridge.dart';

/// Simple network client using configuration injected from [BridgeConfig].
class ApiClient {
  ApiClient({required this.baseUrl, required this.timeout});

  final String baseUrl;
  final Duration timeout;

  Future<String> get(String endpoint) async {
    return 'Response from $baseUrl$endpoint (Timeout: ${timeout.inSeconds}s)';
  }
}

/// Builds an [ApiClient] from the bridge's active [BridgeConfig].
///
/// Shared by [CoreModule] registration and environment hot-switch reconfiguration
/// so both paths always produce identically configured clients.
ApiClient createApiClient(ModularBridge bridge) {
  return ApiClient(
    baseUrl: bridge.config.getString('apiBaseUrl'),
    timeout: bridge.config.getDuration('apiTimeout'),
  );
}

/// Core logging service.
class LoggingService {
  void log(String message) {
    // ignore: avoid_print
    print('[ModularBridge Logger] $message');
  }
}

/// The [CoreModule] provides low-level infrastructure services needed by feature modules.
final class CoreModule extends FeatureModule {
  @override
  String get name => 'CoreModule';

  @override
  void registerDependencies(ModularBridge bridge) {
    // Eager singleton for common logger
    bridge.registerSingleton<LoggingService>(LoggingService());

    // Lazy singleton using type-safe environment configuration values
    bridge.registerLazySingleton<ApiClient>(() => createApiClient(bridge));
  }
}
