import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modular_bridge/modular_bridge.dart';
import 'core_module.dart';

/// Riverpod provider exposing the global [ModularBridge] container.
final bridgeProvider = Provider<ModularBridge>((ref) => ModularBridge.instance);

/// Notifier managing active environment state and runtime flavor hot-switching.
class EnvironmentNotifier extends Notifier<BridgeEnvironment> {
  @override
  BridgeEnvironment build() {
    final bridge = ref.watch(bridgeProvider);

    final sub = bridge.config.onEnvironmentChanged.listen((env) {
      state = env;
    });

    ref.onDispose(sub.cancel);
    return bridge.config.environment;
  }

  /// Hot-switches the application flavor and reconfigures dependencies.
  void switchEnvironment(BridgeEnvironment newEnv) {
    final bridge = ref.read(bridgeProvider);
    bridge.config.switchEnvironment(newEnv);

    // Reconfigure ApiClient for the newly active flavor
    bridge.unregister<ApiClient>();
    bridge.registerLazySingleton<ApiClient>(() {
      return ApiClient(
        baseUrl: bridge.config.getString('apiBaseUrl'),
        timeout: bridge.config.getDuration('apiTimeout'),
      );
    });

    state = newEnv;
  }
}

/// Provider exposing the current [BridgeEnvironment].
final environmentProvider =
    NotifierProvider<EnvironmentNotifier, BridgeEnvironment>(
  EnvironmentNotifier.new,
);

/// Notifier tracking active modules for dynamic loading and unloading in the UI.
class ModulesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final bridge = ref.watch(bridgeProvider);
    return bridge.activeModuleNames;
  }

  /// Dynamically unregisters and disposes a module.
  Future<void> unloadModule(String name) async {
    final bridge = ref.read(bridgeProvider);
    await bridge.unregisterModuleByName(name);
    state = bridge.activeModuleNames;
  }

  /// Dynamically registers and initializes a module.
  Future<void> loadModule(FeatureModule module) async {
    final bridge = ref.read(bridgeProvider);
    await bridge.registerModule(module);
    state = bridge.activeModuleNames;
  }
}

/// Provider exposing the list of registered module names.
final modulesProvider = NotifierProvider<ModulesNotifier, List<String>>(
  ModulesNotifier.new,
);
