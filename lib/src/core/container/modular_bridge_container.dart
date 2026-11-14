import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../config/bridge_config.dart';
import '../../config/bridge_environment.dart';
import '../../event_bus/bridge_event.dart';
import '../../event_bus/bridge_event_bus.dart';
import '../../event_bus/bridge_subscription.dart';
import '../../module/feature_module.dart';
import '../exceptions/bridge_exceptions.dart';
import 'bridge_scope.dart';
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

  /// Creates a [BridgeScope] for registering request/session-scoped
  /// dependencies that are invisible to [get] and disposed together.
  BridgeScope createScope() => BridgeScope(this);

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
  final StreamController<BridgeConfig> _configController =
      StreamController<BridgeConfig>.broadcast();

  final Map<DependencyKey, DependencyDescriptor<dynamic>> _registry = {};
  final Map<String, FeatureModule> _modules = {};
  final List<DependencyKey> _resolutionStack = [];
  final List<FutureOr<void> Function(ModularBridge bridge)> _readyCallbacks =
      [];
  String? _currentlyRegisteringModule;
  bool _modulesReadyNotified = false;
  int _registrationDepth = 0;

  /// Zone key holding the async-local chain of in-flight async dependency
  /// resolutions, tagged with the owning bridge so isolated containers never
  /// interfere. Unlike [_resolutionStack] (used by synchronous resolution),
  /// zone values are scoped per async execution context, so concurrent
  /// [getAsync] calls in unrelated zones never see each other's chains —
  /// while genuine circular async dependencies are still detected.
  static final Object _asyncChainZoneKey = Object();

  List<(ModularBridge, DependencyKey)> get _asyncChain =>
      Zone.current[_asyncChainZoneKey]
          as List<(ModularBridge, DependencyKey)>? ??
      const [];

  /// The active [BridgeConfig] instance.
  BridgeConfig get config => _config;

  /// The active [BridgeEventBus] instance.
  BridgeEventBus get eventBus => _eventBus;

  /// Emits the new [BridgeConfig] whenever [setConfig] swaps the configuration.
  ///
  /// Listeners (e.g. `ModularBridgeProvider`) use this to re-subscribe to the
  /// new config's streams; the old config's streams are no longer monitored.
  Stream<BridgeConfig> get onConfigChanged => _configController.stream;

  /// Names of all currently registered modules.
  List<String> get activeModuleNames => _modules.keys.toList();

  /// An unmodifiable snapshot of every registered [DependencyKey].
  ///
  /// Useful for debugging and introspection of the container state.
  List<DependencyKey> get registeredDependencies =>
      List<DependencyKey>.unmodifiable(_registry.keys);

  /// Updates or reinitializes the [BridgeConfig].
  ///
  /// The previous config is **not** disposed automatically — dispose it
  /// yourself if it is no longer needed. Subscribers are notified via
  /// [onConfigChanged] so they can migrate to the new instance's streams.
  void setConfig(BridgeConfig newConfig) {
    _config = newConfig;
    _configController.add(newConfig);
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

  /// Registers an asynchronous singleton for type [T].
  ///
  /// The [factory] is invoked on the first [getAsync] call and the resulting
  /// future is cached, so concurrent resolutions share a single in-flight
  /// operation. Resolve with [getAsync]; calling [get] on this dependency
  /// throws [BridgeAsyncDependencyException].
  void registerAsyncSingleton<T extends Object>(
    Future<T> Function() factory, {
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
      lifecycle: DependencyLifecycle.asyncSingleton,
      asyncFactory: factory,
      ownerModuleName: _currentlyRegisteringModule,
      onDispose: onDispose,
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

    if (descriptor.lifecycle == DependencyLifecycle.asyncSingleton) {
      throw BridgeAsyncDependencyException(T);
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

  /// Asynchronously resolves an instance of type [T].
  ///
  /// Works for every lifecycle: synchronous dependencies are resolved
  /// immediately and wrapped in a future, while
  /// [DependencyLifecycle.asyncSingleton] dependencies share a single cached
  /// in-flight resolution.
  ///
  /// Throws [BridgeDependencyNotFoundException] if no matching dependency was
  /// registered and [BridgeCircularDependencyException] on dependency loops.
  Future<T> getAsync<T extends Object>({String? instanceName}) async {
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];

    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }

    // Synchronous lifecycles cannot participate in async circular chains:
    // their factories can only call the synchronous [get].
    if (descriptor.lifecycle != DependencyLifecycle.asyncSingleton) {
      return (await descriptor.resolveAsync()) as T;
    }

    // Detect circular async chains within this async context first —
    // awaiting an in-flight future that (transitively) depends on itself
    // would deadlock.
    final chain = _asyncChain;
    if (chain.any((e) => identical(e.$1, this) && e.$2 == key)) {
      throw BridgeCircularDependencyException(
        T,
        chain
            .where((e) => identical(e.$1, this))
            .map((e) => e.$2.type)
            .toList(),
      );
    }

    // An in-flight or completed async resolution is shared by all callers,
    // so concurrent resolutions reuse the same underlying future.
    if (descriptor.hasAsyncResolution) {
      return (await descriptor.resolveAsync()) as T;
    }

    return runZoned(
      () async {
        return (await descriptor.resolveAsync()) as T;
      },
      zoneValues: {
        _asyncChainZoneKey: <(ModularBridge, DependencyKey)>[
          ...chain,
          (this, key),
        ],
      },
    );
  }

  /// Attempts to asynchronously resolve an instance of type [T], returning
  /// `null` if it is not registered. Resolution errors are propagated.
  Future<T?> tryGetAsync<T extends Object>({String? instanceName}) async {
    if (!isRegistered<T>(instanceName: instanceName)) return null;
    return getAsync<T>(instanceName: instanceName);
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

      // Guard the ready hook while init runs: modules registered from inside
      // init() must not trigger onModulesReady before the outer module
      // finishes initializing.
      _registrationDepth++;
      try {
        await module.init(this);
      } finally {
        _registrationDepth--;
      }
    } catch (_) {
      await _rollbackModuleRegistration(module);
      rethrow;
    }

    if (_registrationDepth == 0) {
      _notifyModulesReadyIfNeeded();
    }
  }

  /// Registers a callback invoked whenever all modules have been registered
  /// and initialized (the "modules ready" state).
  ///
  /// If modules are already registered when this is called, the callback is
  /// invoked immediately. The hook re-arms automatically when the last module
  /// is unregistered or [reset] is called, so callbacks fire again on the
  /// next registration cycle. Callback errors are reported via
  /// [FlutterError.reportError] and never break module registration.
  void onModulesReady(FutureOr<void> Function(ModularBridge bridge) callback) {
    _readyCallbacks.add(callback);
    if (_modulesReadyNotified) {
      _invokeReadyCallback(callback);
    }
  }

  void _notifyModulesReadyIfNeeded() {
    if (_modulesReadyNotified || _modules.isEmpty) return;
    _modulesReadyNotified = true;
    for (final callback in List.of(_readyCallbacks)) {
      _invokeReadyCallback(callback);
    }
  }

  void _invokeReadyCallback(FutureOr<void> Function(ModularBridge) callback) {
    try {
      final result = callback(this);
      if (result is Future<void>) {
        unawaited(result.catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'modular_bridge',
              context:
                  ErrorDescription('While running onModulesReady callback'),
            ),
          );
        }));
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'modular_bridge',
          context: ErrorDescription('While running onModulesReady callback'),
        ),
      );
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
  ///
  /// [onModulesReady] callbacks fire once after the whole batch completes,
  /// not after each individual module.
  ///
  /// If a module fails to register, previously registered modules **remain
  /// active** (best-effort batch semantics); only the failed module is rolled
  /// back. To guarantee an all-or-nothing batch, wrap the call and invoke
  /// [reset] on failure.
  Future<void> registerModules(List<FeatureModule> modules) async {
    _registrationDepth++;
    try {
      for (final module in modules) {
        await registerModule(module);
      }
    } finally {
      _registrationDepth--;
    }
    _notifyModulesReadyIfNeeded();
  }

  /// Checks whether a module of type [M] is currently registered.
  bool isModuleRegistered<M extends FeatureModule>() {
    return _modules.values.any((m) => m is M);
  }

  /// Retrieves the registered module instance of type [M].
  ///
  /// Throws [BridgeModuleNotFoundException] if no module of type [M] is registered.
  /// If multiple instances of the same module type are registered under
  /// different names, the first match is returned — use
  /// [unregisterModuleByName] to target a specific instance.
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
  /// If multiple instances of the same module type are registered under
  /// different names, the first match is returned.
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
    if (_modules.isEmpty) {
      // Re-arm the onModulesReady hook for the next registration cycle.
      _modulesReadyNotified = false;
    }
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

  /// Returns a stream that replays the most recent event of type [T] (if any)
  /// to each new listener before emitting live events.
  Stream<T> onLatest<T extends BridgeEvent>() => _eventBus.onLatest<T>();

  /// Completes with the next event of type [T], or throws a [TimeoutException]
  /// if [timeout] elapses first.
  Future<T> once<T extends BridgeEvent>({Duration? timeout}) =>
      _eventBus.once<T>(timeout: timeout);

  // ---------------------------------------------------------------------------
  // RESET & CLEANUP
  // ---------------------------------------------------------------------------

  /// Returns a list of detected leak/integrity issues in the container.
  ///
  /// Intended for test verification after [reset] or module teardown.
  /// An empty list means no issues were detected. Note that active event bus
  /// subscriptions are reported but may be intentional while modules are
  /// registered.
  @visibleForTesting
  List<String> debugLeakReport() {
    final issues = <String>[];

    if (_resolutionStack.isNotEmpty) {
      issues.add(
        'Dependency resolution stack is not empty: '
        '${_resolutionStack.map((k) => k.toString()).join(' -> ')}',
      );
    }

    final activeSubscriptions = _eventBus.activeSubscriptionCount;
    if (activeSubscriptions > 0) {
      issues.add('$activeSubscriptions active event bus subscription(s)');
    }

    return issues;
  }

  /// Throws a [StateError] if [debugLeakReport] detects any issues.
  @visibleForTesting
  void assertNoLeaks() {
    final issues = debugLeakReport();
    if (issues.isNotEmpty) {
      throw StateError('ModularBridge leak/integrity issues detected:\n'
          '${issues.map((i) => ' - $i').join('\n')}');
    }
  }

  /// Completely resets the container.
  ///
  /// Disposes all registered singletons, unregisters modules, cancels event
  /// subscriptions, and resets the resolution stack. Ideal for test `tearDown`.
  Future<void> reset() async {
    _resolutionStack.clear();
    _registrationDepth = 0;

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
    _modulesReadyNotified = false;

    // Dispose and clear all dependency descriptors
    for (final descriptor in _registry.values) {
      descriptor.dispose();
    }
    _registry.clear();

    // Clear event bus subscriptions
    await _eventBus.clearSubscriptions();
  }
}
