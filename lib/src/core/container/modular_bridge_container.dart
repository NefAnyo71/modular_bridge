import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../config/bridge_config.dart';
import '../../config/bridge_environment.dart';
import '../../event_bus/bridge_event.dart';
import '../../event_bus/bridge_event_bus.dart';
import '../../event_bus/bridge_subscription.dart';
import '../../module/feature_module.dart';
import '../exceptions/bridge_exceptions.dart';
import 'dependency_descriptor.dart';

/// Central dependency injection container, module coordinator, and event router.
///
/// Use [ModularBridge.instance] (or [ModularBridge.I]) for the default app-wide container,
/// or [ModularBridge.createIsolated] to instantiate isolated containers for testing.
class ModularBridge {
  /// Default internal constructor.
  ModularBridge({
    BridgeConfig? config,
    BridgeEventBus? eventBus,
  })  : _config = config ?? BridgeConfig(environment: BridgeEnvironment.dev),
        _eventBus = eventBus ?? BridgeEventBus();

  static ModularBridge _instance = ModularBridge();

  /// The global, app-wide singleton instance of [ModularBridge].
  static ModularBridge get instance => _instance;

  /// Shorthand alias for [ModularBridge.instance].
  static ModularBridge get I => _instance;

  /// Creates a completely fresh and isolated [ModularBridge] container.
  ///
  /// Useful for hermetic unit and integration tests where global state must not leak.
  factory ModularBridge.createIsolated({
    BridgeConfig? config,
    BridgeEventBus? eventBus,
  }) {
    return ModularBridge(config: config, eventBus: eventBus);
  }

  /// Sets the global instance, primarily used for test harnesses.
  @visibleForTesting
  static void setMockInstance(ModularBridge bridge) {
    _instance = bridge;
  }

  /// Resets the global instance to a fresh container.
  ///
  /// Useful in test `tearDown` blocks after [setMockInstance] was used.
  @visibleForTesting
  static void resetInstance() {
    _instance = ModularBridge();
  }

  BridgeConfig _config;
  final BridgeEventBus _eventBus;

  final Map<DependencyKey, DependencyDescriptor<dynamic>> _registry = {};
  final Map<String, FeatureModule> _modules = {};
  final List<DependencyKey> _resolutionStack = [];
  String? _currentlyRegisteringModule;

  /// The active [BridgeConfig] instance.
  BridgeConfig get config => _config;

  /// The active [BridgeEventBus] instance.
  BridgeEventBus get eventBus => _eventBus;

  /// Names of all currently registered modules.
  List<String> get activeModuleNames => _modules.keys.toList();

  /// An unmodifiable snapshot of every registered [DependencyKey].
  ///
  /// Useful for debugging and introspection of the container state.
  List<DependencyKey> get registeredDependencies =>
      List<DependencyKey>.unmodifiable(_registry.keys);

  /// Updates or reinitializes the [BridgeConfig].
  void setConfig(BridgeConfig newConfig) {
    _config = newConfig;
  }

  // ---------------------------------------------------------------------------
  // DEPENDENCY REGISTRATION
  // ---------------------------------------------------------------------------

  /// Registers an existing [instance] as an eager singleton for type [T].
  ///
  /// Set [override] to `true` to replace any existing registration.
  /// An optional [onDispose] callback can be provided to release resources.
  void registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
  }) {
    final key = DependencyKey(T, instanceName);
    if (_registry.containsKey(key) && !override) {
      throw BridgeDependencyAlreadyRegisteredException(T,
          instanceName: instanceName);
    }

    if (override && _registry.containsKey(key)) {
      _registry[key]?.dispose();
    }

    _registry[key] = DependencyDescriptor<T>(
      key: key,
      lifecycle: DependencyLifecycle.singleton,
      factory: () => instance,
      instance: instance,
      ownerModuleName: _currentlyRegisteringModule,
      onDispose: onDispose,
    );
  }

  /// Registers a lazy singleton for type [T], instantiated on its first resolution.
  ///
  /// Subsequent calls to [get] will return the cached instance.
  void registerLazySingleton<T extends Object>(
    T Function() factory, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
  }) {
    final key = DependencyKey(T, instanceName);
    if (_registry.containsKey(key) && !override) {
      throw BridgeDependencyAlreadyRegisteredException(T,
          instanceName: instanceName);
    }

    if (override && _registry.containsKey(key)) {
      _registry[key]?.dispose();
    }

    _registry[key] = DependencyDescriptor<T>(
      key: key,
      lifecycle: DependencyLifecycle.lazySingleton,
      factory: factory,
      ownerModuleName: _currentlyRegisteringModule,
      onDispose: onDispose,
    );
  }

  /// Registers a transient factory for type [T].
  ///
  /// A brand new instance will be generated upon every call to [get].
  void registerFactory<T extends Object>(
    T Function() factory, {
    String? instanceName,
    bool override = false,
  }) {
    final key = DependencyKey(T, instanceName);
    if (_registry.containsKey(key) && !override) {
      throw BridgeDependencyAlreadyRegisteredException(T,
          instanceName: instanceName);
    }

    if (override && _registry.containsKey(key)) {
      _registry[key]?.dispose();
    }

    _registry[key] = DependencyDescriptor<T>(
      key: key,
      lifecycle: DependencyLifecycle.factory,
      factory: factory,
      ownerModuleName: _currentlyRegisteringModule,
    );
  }

  /// Replaces an existing dependency with a mock or test instance in a single line.
  ///
  /// If the dependency has not been registered before, it will be added as a singleton.
  void override<T extends Object>(
    T instance, {
    String? instanceName,
  }) {
    registerSingleton<T>(
      instance,
      instanceName: instanceName,
      override: true,
    );
  }

  // ---------------------------------------------------------------------------
  // DEPENDENCY RESOLUTION
  // ---------------------------------------------------------------------------

  /// Resolves an instance of type [T].
  ///
  /// Throws [BridgeDependencyNotFoundException] if no matching dependency was registered.
  /// Throws [BridgeCircularDependencyException] if a circular reference is encountered.
  T get<T extends Object>({String? instanceName}) {
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];

    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }

    if (_resolutionStack.contains(key)) {
      throw BridgeCircularDependencyException(
        T,
        _resolutionStack.map((k) => k.type).toList(),
      );
    }

    _resolutionStack.add(key);
    try {
      final resolved = descriptor.resolve();
      return resolved as T;
    } finally {
      _resolutionStack.removeLast();
    }
  }

  /// Attempts to resolve an instance of type [T], returning `null` if it is
  /// not registered. Errors raised while creating a registered dependency are
  /// propagated to the caller.
  T? tryGet<T extends Object>({String? instanceName}) {
    if (!isRegistered<T>(instanceName: instanceName)) return null;
    return get<T>(instanceName: instanceName);
  }

  /// Callable syntax shortcut for [get].
  ///
  /// Example:
  /// ```dart
  /// final repo = bridge<AuthRepository>();
  /// ```
  T call<T extends Object>({String? instanceName}) =>
      get<T>(instanceName: instanceName);

  /// Checks whether a dependency of type [T] is registered.
  bool isRegistered<T extends Object>({String? instanceName}) {
    final key = DependencyKey(T, instanceName);
    return _registry.containsKey(key);
  }

  /// Unregisters and disposes the dependency of type [T].
  void unregister<T extends Object>({String? instanceName}) {
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry.remove(key);
    descriptor?.dispose();
  }

  // ---------------------------------------------------------------------------
  // MODULE LIFECYCLE MANAGEMENT
  // ---------------------------------------------------------------------------

  /// Registers and initializes a single [FeatureModule].
  ///
  /// Validates dependencies, registers bindings, and triggers [FeatureModule.init].
  /// If registration or initialization fails, the module's resources and
  /// dependencies are rolled back before the original error is rethrown.
  Future<void> registerModule(FeatureModule module) async {
    final moduleName = module.name;
    if (_modules.containsKey(moduleName)) {
      throw BridgeModuleAlreadyRegisteredException(moduleName);
    }

    // Verify module dependencies
    for (final depType in module.dependencies) {
      final isFound = _modules.values.any((m) => m.runtimeType == depType);
      if (!isFound) {
        throw BridgeModuleMissingDependencyException(
          moduleName: moduleName,
          missingDependency: depType,
        );
      }
    }

    _modules[moduleName] = module;

    try {
      _currentlyRegisteringModule = moduleName;
      try {
        module.registerDependencies(this);
      } finally {
        _currentlyRegisteringModule = null;
      }

      await module.init(this);
    } catch (_) {
      await _rollbackModuleRegistration(module);
      rethrow;
    }
  }

  Future<void> _rollbackModuleRegistration(FeatureModule module) async {
    final moduleName = module.name;

    try {
      await module.dispose(this);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'modular_bridge',
          context: ErrorDescription(
            'While rolling back failed module registration for $moduleName',
          ),
        ),
      );
    }

    try {
      await _eventBus.cancelSubscriptionsForOwner(moduleName);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'modular_bridge',
          context: ErrorDescription(
            'While canceling subscriptions for failed module $moduleName',
          ),
        ),
      );
    }

    final keysToRemove = _registry.entries
        .where((entry) => entry.value.ownerModuleName == moduleName)
        .map((entry) => entry.key)
        .toList();

    for (final key in keysToRemove) {
      _registry.remove(key)?.dispose();
    }

    _modules.remove(moduleName);
  }

  /// Sequentially registers and initializes multiple [FeatureModule] instances.
  Future<void> registerModules(List<FeatureModule> modules) async {
    for (final module in modules) {
      await registerModule(module);
    }
  }

  /// Checks whether a module of type [M] is currently registered.
  bool isModuleRegistered<M extends FeatureModule>() {
    return _modules.values.any((m) => m is M);
  }

  /// Retrieves the registered module instance of type [M].
  ///
  /// Throws [BridgeModuleNotFoundException] if no module of type [M] is registered.
  M getModule<M extends FeatureModule>() {
    for (final module in _modules.values) {
      if (module is M) {
        return module;
      }
    }
    throw BridgeModuleNotFoundException(M.toString());
  }

  /// Attempts to retrieve the registered module instance of type [M],
  /// returning `null` if no module of type [M] is registered.
  M? tryGetModule<M extends FeatureModule>() {
    for (final module in _modules.values) {
      if (module is M) {
        return module;
      }
    }
    return null;
  }

  /// Returns the names of registered modules that declare a module of type
  /// [moduleType] in their [FeatureModule.dependencies].
  List<String> moduleDependents(Type moduleType) {
    return _modules.values
        .where((m) => m.dependencies.contains(moduleType))
        .map((m) => m.name)
        .toList();
  }

  void _ensureNoDependents(FeatureModule module, {required bool force}) {
    if (force) return;
    final dependents = moduleDependents(module.runtimeType)
        .where((n) => n != module.name)
        .toList();
    if (dependents.isNotEmpty) {
      throw BridgeModuleInUseException(
        moduleName: module.name,
        dependentModules: dependents,
      );
    }
  }

  /// Unregisters a module of type [M], triggering its dispose lifecycle and
  /// tearing down its registered dependencies and event subscriptions.
  ///
  /// Throws [BridgeModuleInUseException] if other registered modules declare
  /// this module as a dependency, unless [force] is `true`.
  Future<void> unregisterModule<M extends FeatureModule>(
      {bool force = false}) async {
    final module = _modules.values.cast<FeatureModule?>().firstWhere(
          (m) => m is M,
          orElse: () => null,
        );

    if (module == null) {
      throw BridgeModuleNotFoundException(M.toString());
    }

    _ensureNoDependents(module, force: force);
    await _unregisterModuleInternal(module);
  }

  /// Unregisters a module by its identifier [moduleName].
  ///
  /// Throws [BridgeModuleInUseException] if other registered modules declare
  /// this module as a dependency, unless [force] is `true`.
  Future<void> unregisterModuleByName(String moduleName,
      {bool force = false}) async {
    final module = _modules[moduleName];
    if (module == null) {
      throw BridgeModuleNotFoundException(moduleName);
    }
    _ensureNoDependents(module, force: force);
    await _unregisterModuleInternal(module);
  }

  Future<void> _unregisterModuleInternal(FeatureModule module) async {
    final moduleName = module.name;

    // 1. Invoke module dispose hook (cancels its internal subscriptions)
    await module.dispose(this);

    // 2. Cancel all event bus subscriptions tagged with this module's name
    await _eventBus.cancelSubscriptionsForOwner(moduleName);

    // 3. Remove all dependencies registered on behalf of this module
    final keysToRemove = _registry.entries
        .where((entry) => entry.value.ownerModuleName == moduleName)
        .map((entry) => entry.key)
        .toList();

    for (final key in keysToRemove) {
      final descriptor = _registry.remove(key);
      descriptor?.dispose();
    }

    _modules.remove(moduleName);
  }

  // ---------------------------------------------------------------------------
  // EVENT BUS DELEGATIONS
  // ---------------------------------------------------------------------------

  /// Publishes an event through the [ModularBridge.eventBus].
  void publish<T extends BridgeEvent>(T event) => _eventBus.publish(event);

  /// Returns a stream of events of type [T] from the [ModularBridge.eventBus].
  Stream<T> on<T extends BridgeEvent>() => _eventBus.on<T>();

  /// Subscribes to events of type [T] via the [ModularBridge.eventBus].
  BridgeSubscription subscribe<T extends BridgeEvent>(
    void Function(T event) onData, {
    String? ownerId,
  }) {
    return _eventBus.subscribe<T>(onData, ownerId: ownerId);
  }

  // ---------------------------------------------------------------------------
  // RESET & CLEANUP
  // ---------------------------------------------------------------------------

  /// Completely resets the container.
  ///
  /// Disposes all registered singletons, unregisters modules, cancels event
  /// subscriptions, and resets the resolution stack. Ideal for test `tearDown`.
  Future<void> reset() async {
    _resolutionStack.clear();

    // Dispose modules in reverse order
    final moduleList = _modules.values.toList().reversed;
    for (final module in moduleList) {
      try {
        await module.dispose(this);
      } catch (e, st) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'modular_bridge',
            context: ErrorDescription('While disposing module ${module.name}'),
          ),
        );
      }
    }
    _modules.clear();

    // Dispose and clear all dependency descriptors
    for (final descriptor in _registry.values) {
      descriptor.dispose();
    }
    _registry.clear();

    // Clear event bus subscriptions
    await _eventBus.clearSubscriptions();
  }
}
