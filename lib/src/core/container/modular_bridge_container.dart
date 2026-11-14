import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../../config/bridge_config.dart';
import '../../config/bridge_environment.dart';
import '../../event_bus/bridge_event.dart';
import '../../event_bus/bridge_event_bus.dart';
import '../../event_bus/bridge_subscription.dart';
import '../../module/feature_module.dart';
import '../annotations.dart';
import '../errors/bridge_error_reporter.dart';
import '../exceptions/bridge_exceptions.dart';
import 'bridge_scope.dart';
import 'dependency_descriptor.dart';
import 'dependency_event.dart';
import 'dependency_graph.dart';
import 'dependency_metrics.dart';
import 'resolution_context.dart';

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
        _eventBus = eventBus ?? BridgeEventBus() {
    _configValueSubscription =
        _config.onChanged.listen((_) => _notifyConfigBindings());
    _configSwapSubscription = _configController.stream.listen((_) {
      _resubscribeConfigBindings();
      _notifyConfigBindings();
    });
  }

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
  BridgeScope createScope({String? scopeName}) {
    _ensureActive();
    return BridgeScope(this, scopeName: scopeName);
  }

  /// Creates a [BridgeScope], runs [init] against it, seals it against
  /// further registrations, and returns it.
  ///
  /// If [init] throws, the scope is disposed before the error propagates.
  Future<BridgeScope> createScopeAsync([
    FutureOr<void> Function(BridgeScope scope)? init,
  ]) async {
    final scope = createScope();
    try {
      if (init != null) {
        await init(scope);
      }
      scope.seal();
      return scope;
    } catch (_) {
      await scope.dispose();
      rethrow;
    }
  }

  /// Creates a new registration scope and makes it the active scope.
  ///
  /// While a scope is on [scopeStack], registrations made through this bridge
  /// are stored in the top scope and resolutions check the scope chain before
  /// falling back to the root registry.
  ///
  /// [init] runs synchronously after the scope is pushed; [dispose] runs when
  /// the scope is popped or dropped. Set [isFinal] to seal the scope against
  /// later registrations.
  BridgeScope pushNewScope({
    String? scopeName,
    void Function(ModularBridge bridge)? init,
    FutureOr<void> Function()? dispose,
    bool isFinal = false,
  }) {
    _ensureActive();
    final scope = BridgeScope(
      this,
      parent: currentScope,
      scopeName: scopeName,
      onDisposeCallback: dispose,
    );
    _scopeStack.add(scope);
    _notifyScopeChanged(true);
    try {
      init?.call(this);
      if (isFinal) scope.seal();
    } catch (_) {
      _scopeStack.remove(scope);
      unawaited(scope.dispose());
      _notifyScopeChanged(false);
      rethrow;
    }
    return scope;
  }

  /// Async variant of [pushNewScope]; [init] may return a [Future].
  Future<BridgeScope> pushNewScopeAsync({
    String? scopeName,
    FutureOr<void> Function(ModularBridge bridge)? init,
    FutureOr<void> Function()? dispose,
  }) async {
    _ensureActive();
    final scope = BridgeScope(
      this,
      parent: currentScope,
      scopeName: scopeName,
      onDisposeCallback: dispose,
    );
    _scopeStack.add(scope);
    _notifyScopeChanged(true);
    try {
      if (init != null) {
        await init(this);
      }
    } catch (_) {
      _scopeStack.remove(scope);
      await scope.dispose();
      _notifyScopeChanged(false);
      rethrow;
    }
    return scope;
  }

  /// The currently active scope, or `null` when the root registry is active.
  BridgeScope? get currentScope =>
      _scopeStack.isEmpty ? null : _scopeStack.last;

  /// Name of the currently active scope, or `null` when the root registry is
  /// active or the top scope is unnamed.
  String? get currentScopeName => currentScope?.scopeName;

  /// Names of scopes currently on the scope stack, bottom to top.
  List<String> get activeScopeNames => _scopeStack
      .map((s) => s.scopeName ?? 'scope#${identityHashCode(s)}')
      .toList(growable: false);

  /// Optional callback invoked after every scope stack push/pop.
  /// The boolean is `true` for pushes.
  void Function(bool pushed)? onScopeChanged;

  void _notifyScopeChanged(bool pushed) {
    try {
      onScopeChanged?.call(pushed);
    } catch (error, stackTrace) {
      reportBridgeError(
        error,
        stackTrace,
        context: 'While running onScopeChanged callback',
      );
    }
  }

  /// Disposes and removes the top scope, reactivating the previous scope.
  Future<void> popScope() async {
    _ensureActive();
    if (_scopeStack.isEmpty) {
      throw StateError('Cannot pop a scope: the scope stack is empty.');
    }
    final scope = _scopeStack.removeLast();
    try {
      await scope.dispose();
    } finally {
      _notifyScopeChanged(false);
    }
  }

  /// Disposes and removes the named scope and every scope above it.
  Future<void> dropScope(String scopeName) async {
    _ensureActive();
    final index = _scopeStack.indexWhere((s) => s.scopeName == scopeName);
    if (index < 0) {
      throw BridgeScopeNotFoundException(scopeName);
    }
    while (_scopeStack.length > index) {
      await popScope();
    }
  }

  /// Pops scopes until the scope named [name] becomes active.
  ///
  /// When [inclusive] is true the named scope itself is also popped.
  /// Returns `false` when no scope with [name] exists.
  Future<bool> popScopesTill(String name, {bool inclusive = true}) async {
    _ensureActive();
    final index = _scopeStack.indexWhere((s) => s.scopeName == name);
    if (index < 0) return false;
    final targetLength = inclusive ? index : index + 1;
    while (_scopeStack.length > targetLength) {
      await popScope();
    }
    return true;
  }

  /// Whether a scope named [scopeName] is currently on the active scope
  /// stack (i.e. pushed via [pushNewScope] and not yet popped).
  ///
  /// For scopes that exist but are not on the stack, use [findScope].
  bool isScopeActive(String scopeName) =>
      _scopeStack.any((s) => s.scopeName == scopeName);

  /// Finds a live scope by name, searching the stack first and then any
  /// tracked explicit scopes.
  BridgeScope? findScope(String scopeName) {
    for (final scope in _scopeStack.reversed) {
      if (scope.scopeName == scopeName) return scope;
    }
    for (final scope in _liveScopes) {
      if (scope.scopeName == scopeName && !scope.isDisposed) return scope;
    }
    return null;
  }

  /// Sets the global instance, primarily used for test harnesses.
  @visibleForTesting()
  static void setMockInstance(ModularBridge bridge) {
    _instance = bridge;
  }

  /// Resets the global instance to a fresh container.
  ///
  /// Useful in test `tearDown` blocks after [setMockInstance] was used.
  @visibleForTesting()
  static void resetInstance() {
    _instance = ModularBridge();
  }

  BridgeConfig _config;
  final BridgeEventBus _eventBus;
  final StreamController<BridgeConfig> _configController =
      StreamController<BridgeConfig>.broadcast();
  final StreamController<DependencyRegistrationEvent> _dependencyEvents =
      StreamController<DependencyRegistrationEvent>.broadcast();

  final Map<DependencyKey, DependencyDescriptor<dynamic>> _registry = {};
  final Map<String, FeatureModule> _modules = {};
  final List<FutureOr<void> Function(ModularBridge bridge)> _readyCallbacks =
      [];
  final List<BridgeScope> _scopeStack = [];
  final Set<BridgeScope> _liveScopes = {};
  final List<Future<void> Function()> _configBindings = [];
  late StreamSubscription<void> _configValueSubscription;
  late StreamSubscription<BridgeConfig> _configSwapSubscription;
  int _registrationCounter = 0;
  int _registrationDepth = 0;
  bool _modulesReadyNotified = false;
  bool _isDisposed = false;

  /// When `true`, registering an already-registered dependency silently
  /// replaces it (equivalent to passing `override: true` everywhere).
  ///
  /// Defaults to `false`. Scope registrations consult this flag on the root
  /// bridge as well.
  bool allowReassignment = false;

  /// Zone key holding the name of the [FeatureModule] currently executing
  /// `registerDependencies`/`init`. Zone values propagate across `await`
  /// boundaries, so dependencies registered by an async module body are still
  /// attributed to the correct owner even when module registrations run in
  /// parallel.
  static final Object _moduleOwnerZoneKey = Object();

  String? get _currentModuleOwner =>
      Zone.current[_moduleOwnerZoneKey] as String?;

  /// Module owner visible to [BridgeScope] registrations.
  ///
  /// Internal bridge between the zone-based module context and scope-local
  /// descriptors; not part of the public API contract.
  String? get currentModuleOwnerForScope => _currentModuleOwner;

  /// The active [BridgeConfig] instance.
  BridgeConfig get config => _config;

  /// The active [BridgeEventBus] instance.
  BridgeEventBus get eventBus => _eventBus;

  /// Emits the new [BridgeConfig] whenever [setConfig] swaps the configuration.
  ///
  /// Listeners (e.g. `ModularBridgeProvider`) use this to re-subscribe to the
  /// new config's streams; the old config's streams are no longer monitored.
  Stream<BridgeConfig> get onConfigChanged => _configController.stream;

  /// Broadcast stream of dependency registration changes across the root
  /// registry and every live [BridgeScope].
  ///
  /// Useful for building DevTools-style inspectors or audit logs.
  Stream<DependencyRegistrationEvent> get onDependencyEvents =>
      _dependencyEvents.stream;

  /// Emits a dependency change event. Called by [BridgeScope]; not part of
  /// the public API contract.
  void notifyDependencyEvent(
    DependencyChangeKind kind,
    DependencyDescriptor<dynamic> descriptor,
  ) {
    if (_isDisposed || _dependencyEvents.isClosed) return;
    _dependencyEvents.add(DependencyRegistrationEvent(
      kind: kind,
      info: DependencyInfo.fromDescriptor(descriptor),
      scopeName: descriptor.scopeName,
    ));
  }

  /// Names of all currently registered modules.
  List<String> get activeModuleNames => _modules.keys.toList();

  /// An unmodifiable snapshot of every registered [DependencyKey].
  ///
  /// Useful for debugging and introspection of the container state.
  List<DependencyKey> get registeredDependencies =>
      List<DependencyKey>.unmodifiable(_registry.keys);

  /// Resolution metrics collected across the root registry and all scopes.
  ///
  /// Records per-key resolution counts, cache hits, failures, and durations.
  /// Reset with [resetMetrics].
  final DependencyMetrics metrics = DependencyMetrics();

  /// Clears all collected resolution metrics.
  void resetMetrics() => metrics.reset();

  /// Registration metadata for dependencies owned by the root registry.
  List<DependencyInfo> get dependencyInfo => _registry.values
      .map(DependencyInfo.fromDescriptor)
      .toList(growable: false);

  /// Whether [dispose] has been called on this container.
  bool get isDisposed => _isDisposed;

  /// Updates or reinitializes the [BridgeConfig].
  ///
  /// The previous config is **not** disposed automatically — dispose it
  /// yourself if it is no longer needed. Subscribers are notified via
  /// [onConfigChanged] so they can migrate to the new instance's streams.
  /// Config-bound dependencies registered via [registerConfigBinding] are
  /// reset so they re-decode on next resolution.
  void setConfig(BridgeConfig newConfig) {
    _ensureActive();
    _config = newConfig;
    _configController.add(newConfig);
  }

  // ---------------------------------------------------------------------------
  // CONFIG-BOUND DEPENDENCIES
  // ---------------------------------------------------------------------------

  /// Registers a lazy singleton whose value is decoded from [BridgeConfig]
  /// and automatically reset whenever the effective configuration changes.
  ///
  /// This is the DI-side counterpart of `config.onChanged`: the next
  /// resolution after a config change produces a fresh decoded value and the
  /// previous instance's `onDispose` hook runs.
  void registerConfigBinding<T extends Object>({
    required String configKey,
    required T Function(dynamic value) decoder,
    dynamic defaultValue,
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
    bool signalsReady = false,
  }) {
    final scope = currentScope;
    final key = DependencyKey(T, instanceName);
    Future<void> reset() {
      if (scope != null) {
        return scope.resetLazySingleton<T>(
          instanceName: instanceName,
          disposeHooks: true,
        );
      }
      return _resetLazySingletonByKey(key, disposeHooks: true);
    }

    if (scope != null) {
      scope.registerLazySingleton<T>(
        () => decoder(
            _config.get<dynamic>(configKey, defaultValue: defaultValue)),
        instanceName: instanceName,
        override: override,
        onDispose: onDispose,
        signalsReady: signalsReady,
      );
    } else {
      registerLazySingleton<T>(
        () => decoder(
            _config.get<dynamic>(configKey, defaultValue: defaultValue)),
        instanceName: instanceName,
        override: override,
        onDispose: onDispose,
        signalsReady: signalsReady,
      );
    }
    _configBindings.add(reset);
  }

  void _resubscribeConfigBindings() {
    unawaited(_configValueSubscription.cancel());
    _configValueSubscription =
        _config.onChanged.listen((_) => _notifyConfigBindings());
  }

  void _notifyConfigBindings() {
    if (_configBindings.isEmpty) return;
    final resets = List<Future<void> Function()>.of(_configBindings);
    unawaited(Future.wait(resets.map((reset) async {
      try {
        await reset();
      } catch (error, stackTrace) {
        reportBridgeError(
          error,
          stackTrace,
          context: 'While resetting config-bound dependency',
        );
      }
    })));
  }

  Future<void> _resetLazySingletonByKey(
    DependencyKey key, {
    required bool disposeHooks,
  }) async {
    final descriptor = _registry[key];
    if (descriptor == null) return;
    await descriptor.resetLazy(disposeHooks: disposeHooks);
  }

  // ---------------------------------------------------------------------------
  // SCOPE TRACKING (internal)
  // ---------------------------------------------------------------------------

  /// Registers a live scope for diagnostics and config-binding lookups.
  ///
  /// Called by [BridgeScope]; not part of the public API contract.
  void trackScope(BridgeScope scope) {
    _liveScopes.add(scope);
  }

  /// Removes a scope from live tracking after disposal.
  ///
  /// Called by [BridgeScope]; not part of the public API contract.
  void untrackScope(BridgeScope scope) {
    _liveScopes.remove(scope);
  }

  // ---------------------------------------------------------------------------
  // DEPENDENCY REGISTRATION
  // ---------------------------------------------------------------------------

  void _register<T>(
    DependencyLifecycle lifecycle, {
    required DependencyKey key,
    required bool override,
    T Function()? factory,
    Future<T> Function()? asyncFactory,
    T? instance,
    void Function(T instance)? onDispose,
    bool eagerAsync = false,
    bool signalsReady = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
    T Function(Object? param1, Object? param2)? paramFactory,
    Future<T> Function(Object? param1, Object? param2)? paramAsyncFactory,
    bool paramCached = false,
  }) {
    _ensureActive();
    final existing = _registry[key];
    if (existing != null) {
      if (!override && !allowReassignment) {
        throw BridgeDependencyAlreadyRegisteredException(T,
            instanceName: key.name);
      }
      unawaited(existing.dispose());
    }

    final descriptor = DependencyDescriptor<T>(
      key: key,
      lifecycle: lifecycle,
      registrationIndex: _registrationCounter++,
      factory: factory,
      asyncFactory: asyncFactory,
      instance: instance,
      ownerModuleName: _currentModuleOwner,
      onDispose: onDispose,
      eagerAsync: eagerAsync,
      signalsReady: signalsReady,
      dependsOn: List.unmodifiable(dependsOn),
      onCreated: onCreated,
      paramFactory: paramFactory,
      paramAsyncFactory: paramAsyncFactory,
      paramCached: paramCached,
      metrics: metrics,
    );
    _registry[key] = descriptor;
    notifyDependencyEvent(DependencyChangeKind.registered, descriptor);

    if (eagerAsync && lifecycle == DependencyLifecycle.asyncSingleton) {
      // Resolve inside a resolution frame so self-dependent eager factories
      // are detected instead of deadlocking on their own in-flight future.
      unawaited(resolveWithFrameAsync(
        this,
        key,
        () => _registry[key]!.resolveAsync(),
      ).then((_) {}, onError: (_) {}));
    }
  }

  BridgeScope? get _activeScope => currentScope;

  /// Registers an existing [instance] as an eager singleton for type [T].
  ///
  /// Set [override] to `true` to replace any existing registration.
  /// An optional [onDispose] callback can be provided to release resources.
  /// Pass `signalsReady: true` (or implement [WillSignalReady]) to require a
  /// manual `signalReady(instance)` before [allReady] completes.
  void registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
    bool? signalsReady,
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerSingleton<T>(
        instance,
        instanceName: instanceName,
        override: override,
        onDispose: onDispose,
        signalsReady: signalsReady,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.singleton,
      key: DependencyKey(T, instanceName),
      factory: () => instance,
      instance: instance,
      override: override,
      onDispose: onDispose,
      signalsReady: signalsReady ?? instance is WillSignalReady,
      onCreated: onCreated,
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
    bool signalsReady = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerLazySingleton<T>(
        factory,
        instanceName: instanceName,
        override: override,
        onDispose: onDispose,
        signalsReady: signalsReady,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.lazySingleton,
      key: DependencyKey(T, instanceName),
      factory: factory,
      override: override,
      onDispose: onDispose,
      signalsReady: signalsReady,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
  }

  /// Registers a singleton whose factory runs only after [dependsOn]
  /// dependencies are ready.
  ///
  /// The factory receives this bridge; resolution is triggered immediately.
  void registerSingletonWithDependencies<T extends Object>({
    required T Function(ModularBridge bridge) factoryFunc,
    required Iterable<DependencyKey> dependsOn,
    String? instanceName,
    bool override = false,
    bool signalsReady = false,
    void Function(T instance)? onDispose,
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerSingletonWithDependencies<T>(
        factoryFunc: (s) => factoryFunc(this),
        dependsOn: dependsOn,
        instanceName: instanceName,
        override: override,
        signalsReady: signalsReady,
        onDispose: onDispose,
        onCreated: onCreated,
      );
      return;
    }
    registerLazySingleton<T>(
      () => factoryFunc(this),
      instanceName: instanceName,
      override: override,
      onDispose: onDispose,
      signalsReady: signalsReady,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    final pending = getAsync<T>(instanceName: instanceName).then<void>((_) {});
    descriptor?.pendingResult = pending;
    unawaited(pending.whenComplete(() {
      if (identical(descriptor?.pendingResult, pending)) {
        descriptor?.pendingResult = null;
      }
    }));
  }

  /// Async variant of [registerSingletonWithDependencies].
  ///
  /// [factoryFunc] may return a value or a [Future]; it runs only after every
  /// [dependsOn] key has resolved. The registration is an async singleton —
  /// resolve it with [getAsync]. Resolution is triggered immediately so the
  /// registration participates in [allReady].
  void registerSingletonWithDependenciesAsync<T extends Object>({
    required FutureOr<T> Function(ModularBridge bridge) factoryFunc,
    required Iterable<DependencyKey> dependsOn,
    String? instanceName,
    bool override = false,
    bool signalsReady = false,
    void Function(T instance)? onDispose,
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerSingletonWithDependenciesAsync<T>(
        factoryFunc: (s) => factoryFunc(this),
        dependsOn: dependsOn,
        instanceName: instanceName,
        override: override,
        signalsReady: signalsReady,
        onDispose: onDispose,
        onCreated: onCreated,
      );
      return;
    }
    registerAsyncSingleton<T>(
      () async => await factoryFunc(this),
      instanceName: instanceName,
      override: override,
      onDispose: onDispose,
      eager: false,
      signalsReady: signalsReady,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    final pending = getAsync<T>(instanceName: instanceName).then<void>((_) {});
    descriptor?.pendingResult = pending;
    unawaited(pending.whenComplete(() {
      if (identical(descriptor?.pendingResult, pending)) {
        descriptor?.pendingResult = null;
      }
    }));
  }

  /// Registers a transient factory for type [T].
  ///
  /// A brand new instance will be generated upon every call to [get].
  void registerFactory<T extends Object>(
    T Function() factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerFactory<T>(
        factory,
        instanceName: instanceName,
        override: override,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.factory,
      key: DependencyKey(T, instanceName),
      factory: factory,
      override: override,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
  }

  /// Registers an asynchronous singleton for type [T].
  ///
  /// The [factory] is invoked lazily on the first [getAsync] call and the
  /// resulting future is cached, so concurrent resolutions share a single
  /// in-flight operation. Resolve with [getAsync]; calling [get] on this
  /// dependency throws [BridgeAsyncDependencyException].
  ///
  /// Pass `eager: true` to start the resolution immediately at registration
  /// time; eager async singletons
  /// participate in [allReady].
  void registerAsyncSingleton<T extends Object>(
    Future<T> Function() factory, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
    bool eager = false,
    bool signalsReady = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerAsyncSingleton<T>(
        factory,
        instanceName: instanceName,
        override: override,
        onDispose: onDispose,
        eager: eager,
        signalsReady: signalsReady,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.asyncSingleton,
      key: DependencyKey(T, instanceName),
      asyncFactory: factory,
      override: override,
      onDispose: onDispose,
      eagerAsync: eager,
      signalsReady: signalsReady,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
  }

  /// Registers a lazy asynchronous singleton for type [T].
  ///
  /// Alias for [registerAsyncSingleton] with `eager: false`.
  void registerLazySingletonAsync<T extends Object>(
    Future<T> Function() factory, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
    bool signalsReady = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    registerAsyncSingleton<T>(
      factory,
      instanceName: instanceName,
      override: override,
      onDispose: onDispose,
      eager: false,
      signalsReady: signalsReady,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
  }

  /// Registers an eager asynchronous singleton for type [T].
  ///
  /// Alias for [registerAsyncSingleton] with `eager: true`.
  void registerSingletonAsync<T extends Object>(
    Future<T> Function() factory, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
    bool signalsReady = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    registerAsyncSingleton<T>(
      factory,
      instanceName: instanceName,
      override: override,
      onDispose: onDispose,
      eager: true,
      signalsReady: signalsReady,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
  }

  /// Registers an asynchronous transient factory for type [T].
  ///
  /// Every [getAsync] call produces a new instance. Async factories are
  /// never cached and do not participate in [allReady].
  void registerFactoryAsync<T extends Object>(
    Future<T> Function() factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerFactoryAsync<T>(
        factory,
        instanceName: instanceName,
        override: override,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.asyncFactory,
      key: DependencyKey(T, instanceName),
      asyncFactory: factory,
      override: override,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
  }

  /// Registers a transient factory that receives two parameters at
  /// resolution time.
  ///
  /// Resolve with [getParam]; parameters are not part of the registration
  /// key, so multiple parameter combinations share one registration.
  void registerFactoryParam<T extends Object, P1, P2>(
    T Function(P1 param1, P2 param2) factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerFactoryParam<T, P1, P2>(
        factory,
        instanceName: instanceName,
        override: override,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.factory,
      key: DependencyKey(T, instanceName),
      factory: () => throw StateError(
          'Parameter factory ${DependencyKey(T, instanceName)} requires '
          'getParam(param1:, param2:).'),
      override: override,
      dependsOn: dependsOn,
      onCreated: onCreated,
      paramFactory: (p1, p2) => factory(p1 as P1, p2 as P2),
    );
  }

  /// Registers a parameterized factory whose results are cached per
  /// `(param1, param2)` pair.
  void registerCachedFactoryParam<T extends Object, P1, P2>(
    T Function(P1 param1, P2 param2) factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerCachedFactoryParam<T, P1, P2>(
        factory,
        instanceName: instanceName,
        override: override,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.factory,
      key: DependencyKey(T, instanceName),
      factory: () => throw StateError(
          'Cached parameter factory ${DependencyKey(T, instanceName)} '
          'requires getParam(param1:, param2:).'),
      override: override,
      dependsOn: dependsOn,
      onCreated: onCreated,
      paramFactory: (p1, p2) => factory(p1 as P1, p2 as P2),
      paramCached: true,
    );
  }

  /// Registers an async parameterized transient factory.
  void registerFactoryParamAsync<T extends Object, P1, P2>(
    Future<T> Function(P1 param1, P2 param2) factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerFactoryParamAsync<T, P1, P2>(
        factory,
        instanceName: instanceName,
        override: override,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.asyncFactory,
      key: DependencyKey(T, instanceName),
      asyncFactory: () => throw StateError(
          'Async parameter factory ${DependencyKey(T, instanceName)} '
          'requires getParamAsync(param1:, param2:).'),
      override: override,
      dependsOn: dependsOn,
      onCreated: onCreated,
      paramAsyncFactory: (p1, p2) => factory(p1 as P1, p2 as P2),
    );
  }

  /// Registers an async parameterized factory cached per parameter pair.
  void registerCachedFactoryParamAsync<T extends Object, P1, P2>(
    Future<T> Function(P1 param1, P2 param2) factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      scope.registerCachedFactoryParamAsync<T, P1, P2>(
        factory,
        instanceName: instanceName,
        override: override,
        dependsOn: dependsOn,
        onCreated: onCreated,
      );
      return;
    }
    _register<T>(
      DependencyLifecycle.asyncFactory,
      key: DependencyKey(T, instanceName),
      asyncFactory: () => throw StateError(
          'Cached async parameter factory ${DependencyKey(T, instanceName)} '
          'requires getParamAsync(param1:, param2:).'),
      override: override,
      dependsOn: dependsOn,
      onCreated: onCreated,
      paramAsyncFactory: (p1, p2) => factory(p1 as P1, p2 as P2),
      paramCached: true,
    );
  }

  /// Resolves a parameterized factory registered via
  /// [registerFactoryParam]/[registerCachedFactoryParam].
  T getParam<T extends Object, P1, P2>({
    required P1 param1,
    required P2 param2,
    String? instanceName,
  }) {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.getParam<T, P1, P2>(
        param1: param1,
        param2: param2,
        instanceName: instanceName,
      );
    }
    return getParamFromRoot<T, P1, P2>(
      param1: param1,
      param2: param2,
      instanceName: instanceName,
    );
  }

  /// Root-registry parameter resolution used as the scope fallback target.
  T getParamFromRoot<T extends Object, P1, P2>({
    required P1 param1,
    required P2 param2,
    String? instanceName,
  }) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
    return _resolveDescriptorRootSyncParam<T, P1, P2>(
        key, descriptor, param1, param2);
  }

  T _resolveDescriptorRootSyncParam<T, P1, P2>(
    DependencyKey key,
    DependencyDescriptor<dynamic> descriptor,
    P1 param1,
    P2 param2,
  ) {
    if (!descriptor.isParamFactory) {
      throw StateError(
          'Dependency ${key.toString()} is not a parameterized factory.');
    }
    if (descriptor.paramFactory == null) {
      throw BridgeAsyncDependencyException(key.type);
    }
    return resolveWithFrame(this, key, () {
      _resolveDependsOnSync(descriptor);
      return descriptor.resolveParam(param1, param2);
    }) as T;
  }

  /// Asynchronously resolves a parameterized factory.
  ///
  /// Works for both synchronous and asynchronous parameter factories.
  Future<T> getParamAsync<T extends Object, P1, P2>({
    required P1 param1,
    required P2 param2,
    String? instanceName,
  }) {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.getParamAsync<T, P1, P2>(
        param1: param1,
        param2: param2,
        instanceName: instanceName,
      );
    }
    return getParamAsyncFromRoot<T, P1, P2>(
      param1: param1,
      param2: param2,
      instanceName: instanceName,
    );
  }

  /// Root-registry async parameter resolution used as the scope fallback.
  Future<T> getParamAsyncFromRoot<T extends Object, P1, P2>({
    required P1 param1,
    required P2 param2,
    String? instanceName,
  }) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
    return _resolveDescriptorRootAsyncParam<T, P1, P2>(
        key, descriptor, param1, param2);
  }

  Future<T> _resolveDescriptorRootAsyncParam<T, P1, P2>(
    DependencyKey key,
    DependencyDescriptor<dynamic> descriptor,
    P1 param1,
    P2 param2,
  ) {
    return resolveWithFrameAsync<dynamic>(this, key, () async {
      await _resolveDependsOnAsync(descriptor);
      if (descriptor.paramAsyncFactory != null) {
        return descriptor.resolveParamAsync(param1, param2);
      }
      return descriptor.resolveParam(param1, param2);
    }).then((value) => value as T);
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
  /// Throws [BridgeAsyncDependencyException] for async lifecycles — use [getAsync].
  T get<T extends Object>({String? instanceName}) {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.get<T>(instanceName: instanceName);
    }
    return getFromRoot<T>(instanceName: instanceName);
  }

  /// Root-registry resolution used when no scope is active and as the scope
  /// fallback target.
  T getFromRoot<T extends Object>({String? instanceName}) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
    return _resolveDescriptorRootSync(key, descriptor) as T;
  }

  Object? _resolveDescriptorRootSync(
      DependencyKey key, DependencyDescriptor<dynamic> descriptor) {
    if (descriptor.lifecycle == DependencyLifecycle.asyncSingleton ||
        descriptor.lifecycle == DependencyLifecycle.asyncFactory) {
      throw BridgeAsyncDependencyException(key.type);
    }
    return resolveWithFrame(this, key, () {
      _resolveDependsOnSync(descriptor);
      return descriptor.resolve();
    });
  }

  Future<Object?> _resolveDescriptorRootAsync(
      DependencyKey key, DependencyDescriptor<dynamic> descriptor) {
    return resolveWithFrameAsync(this, key, () async {
      await _resolveDependsOnAsync(descriptor);
      if (descriptor.lifecycle != DependencyLifecycle.asyncSingleton &&
          descriptor.lifecycle != DependencyLifecycle.asyncFactory) {
        return descriptor.resolve();
      }
      return descriptor.resolveAsync();
    });
  }

  void _resolveDependsOnSync(DependencyDescriptor<dynamic> descriptor) {
    for (final dep in descriptor.dependsOn) {
      final result = _resolveKeyRoot(dep, async: false);
      if (result is Future<Object?>) {
        throw BridgeAsyncDependencyException(dep.type);
      }
    }
  }

  Future<void> _resolveDependsOnAsync(
      DependencyDescriptor<dynamic> descriptor) async {
    for (final dep in descriptor.dependsOn) {
      await _resolveKeyRoot(dep, async: true);
    }
  }

  /// Resolves a dependency identified by [key] against the root registry.
  ///
  /// Internal resolver used for `dependsOn` orchestration and scope fallback.
  FutureOr<Object?> resolveDependencyKeyFromRoot(
    DependencyKey key, {
    required bool async,
  }) {
    return _resolveKeyRoot(key, async: async);
  }

  FutureOr<Object?> _resolveKeyRoot(
    DependencyKey key, {
    required bool async,
  }) {
    final descriptor = _registry[key];
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(key.type, instanceName: key.name);
    }
    if (async) {
      return _resolveDescriptorRootAsync(key, descriptor);
    }
    return _resolveDescriptorRootSync(key, descriptor);
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
  /// Works for every lifecycle: synchronous dependencies resolve immediately
  /// and are wrapped in a future, while async lifecycles share a single
  /// cached in-flight resolution (singletons) or produce a new instance per
  /// call (factories).
  ///
  /// Throws [BridgeDependencyNotFoundException] if no matching dependency was
  /// registered and [BridgeCircularDependencyException] on dependency loops —
  /// including loops that cross synchronous and asynchronous boundaries or
  /// [BridgeScope] hierarchies.
  Future<T> getAsync<T extends Object>({String? instanceName}) {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.getAsync<T>(instanceName: instanceName);
    }
    return getAsyncFromRoot<T>(instanceName: instanceName);
  }

  /// Root-registry async resolution used when no scope is active.
  Future<T> getAsyncFromRoot<T extends Object>({String? instanceName}) {
    _ensureActive();
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
    return _resolveDescriptorRootAsync(key, descriptor)
        .then((value) => value as T);
  }

  /// Attempts to asynchronously resolve an instance of type [T], returning
  /// `null` if it is not registered. Resolution errors are propagated.
  Future<T?> tryGetAsync<T extends Object>({String? instanceName}) async {
    if (!isRegistered<T>(instanceName: instanceName)) return null;
    return getAsync<T>(instanceName: instanceName);
  }

  /// Resolves every registration of type [T] visible from the current
  /// resolution context — including named instances — nearest scope first.
  List<T> getAll<T extends Object>() {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.getAll<T>();
    }
    return _registry.keys
        .where((key) => key.type == T)
        .map((key) => getFromRoot<T>(instanceName: key.name))
        .toList();
  }

  /// Asynchronously resolves every registration of type [T] visible from the
  /// current resolution context.
  Future<List<T>> getAllAsync<T extends Object>() async {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.getAllAsync<T>();
    }
    final keys = _registry.keys.where((key) => key.type == T).toList();
    return Future.wait(
        keys.map((key) => getAsyncFromRoot<T>(instanceName: key.name)));
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
    final scope = _activeScope;
    if (scope != null) {
      return scope.isRegistered<T>(instanceName: instanceName);
    }
    return isRegisteredFromRoot<T>(instanceName: instanceName);
  }

  /// Root-registry registration check used as the scope fallback target.
  bool isRegisteredFromRoot<T extends Object>({String? instanceName}) {
    return _registry.containsKey(DependencyKey(T, instanceName));
  }

  DependencyDescriptor<dynamic>? findDescriptorFromRoot(DependencyKey key) =>
      _registry[key];

  DependencyDescriptor<dynamic>? findDescriptorByInstanceFromRoot(
      Object instance) {
    for (final descriptor in _registry.values) {
      if (identical(descriptor.cachedInstance, instance)) return descriptor;
    }
    return null;
  }

  /// Returns `true` when [T] has no pending asynchronous resolution.
  ///
  /// For async singletons this means the instance is cached and any required
  /// readiness signal has been sent. Throws
  /// [BridgeDependencyNotFoundException] when [T] is not registered.
  bool isReadySync<T extends Object>({String? instanceName}) {
    final scope = _activeScope;
    if (scope != null) {
      return scope.isReadySync<T>(instanceName: instanceName);
    }
    final descriptor = _requireDescriptor<T>(instanceName: instanceName);
    return descriptor.isReady;
  }

  /// Returns a [Future] that completes when the dependency of type [T] is
  /// ready for synchronous use.
  ///
  /// Synchronous lifecycles complete immediately unless they depend on other
  /// registrations or use `signalsReady`. Async singletons start their
  /// resolution if needed. An optional [timeout] throws a
  /// [TimeoutException] when readiness is not reached in time.
  Future<void> isReady<T extends Object>({
    String? instanceName,
    Duration? timeout,
  }) {
    final scope = _activeScope;
    if (scope != null) {
      return scope.isReady<T>(instanceName: instanceName, timeout: timeout);
    }
    final descriptor = _requireDescriptor<T>(instanceName: instanceName);
    Future<void> ready;
    if (descriptor.lifecycle == DependencyLifecycle.asyncSingleton) {
      ready = descriptor.readiness(startAsyncResolution: true);
    } else if (descriptor.signalsReady ||
        descriptor.dependsOn.isNotEmpty ||
        descriptor.pendingResult != null) {
      ready = descriptor.readiness();
    } else {
      ready = Future<void>.value();
    }
    if (timeout != null) {
      return ready.timeout(
        timeout,
        onTimeout: () => throw BridgeWaitingTimeOutException(
          duration: timeout,
          pending: descriptor.isReady
              ? const []
              : [DependencyKey(T, instanceName).toString()],
          ready: descriptor.isReady
              ? [DependencyKey(T, instanceName).toString()]
              : const [],
        ),
      );
    }
    return ready;
  }

  /// Returns a [Future] that completes when every readiness-tracked
  /// registration has finished.
  ///
  /// This includes eager or in-flight async singletons, `signalsReady`
  /// registrations, and `registerSingletonWithDependencies` orchestrations.
  /// Lazy async singletons that were never started and async transient
  /// factories do not participate unless they were explicitly marked.
  ///
  /// An optional [timeout] throws a [TimeoutException] listing the
  /// dependencies that were still pending.
  Future<void> allReady({
    Duration? timeout,
    bool ignorePendingAsyncCreation = false,
  }) {
    Future<void> ready;
    if (ignorePendingAsyncCreation) {
      ready = Future<void>.value();
    } else {
      ready = Future.wait(
        _readinessDescriptors()
            .where(_countsForAllReady)
            .map((d) => d.readiness()),
      ).then((_) {});
    }
    if (timeout != null) {
      return ready.timeout(
        timeout,
        onTimeout: () {
          final counted = _readinessDescriptors().where(_countsForAllReady);
          return throw BridgeWaitingTimeOutException(
            duration: timeout,
            pending: counted
                .where((d) => !d.isReady)
                .map((d) => d.key.toString())
                .toList(growable: false),
            ready: counted
                .where((d) => d.isReady)
                .map((d) => d.key.toString())
                .toList(growable: false),
          );
        },
      );
    }
    return ready;
  }

  /// Synchronous counterpart of [allReady].
  bool allReadySync({bool ignorePendingAsyncCreation = false}) {
    if (ignorePendingAsyncCreation) return true;
    return _readinessDescriptors()
        .every((d) => !_countsForAllReady(d) || d.isReady);
  }

  /// Eagerly resolves every singleton-style registration in the root
  /// registry and all live scopes.
  ///
  /// Covers `singleton`, `lazySingleton`, and `asyncSingleton` lifecycles
  /// (including `signalsReady` registrations — readiness signalling is still
  /// required for [allReady]). Transient factories and parameterized
  /// factories are skipped because they require arguments or produce a new
  /// instance per call.
  ///
  /// Resolution errors propagate to the caller; use this during app startup
  /// to surface DI misconfigurations before first use.
  ///
  /// Pass [ownerModule] (a [FeatureModule.name]) to warm up only the
  /// dependencies registered on behalf of that module.
  Future<void> warmup({bool includeScopes = true, String? ownerModule}) async {
    _ensureActive();
    bool warmable(DependencyDescriptor<dynamic> d) =>
        !d.isParamFactory &&
        (ownerModule == null || d.ownerModuleName == ownerModule) &&
        (d.lifecycle == DependencyLifecycle.singleton ||
            d.lifecycle == DependencyLifecycle.lazySingleton ||
            d.lifecycle == DependencyLifecycle.asyncSingleton);

    final futures = <Future<void>>[];
    for (final descriptor in _registry.values) {
      if (warmable(descriptor)) {
        futures.add(() async {
          await _resolveKeyRoot(descriptor.key, async: true);
        }());
      }
    }
    if (includeScopes) {
      for (final scope in _liveScopes) {
        if (scope.isDisposed) continue;
        for (final descriptor in scope.localDescriptors) {
          if (warmable(descriptor)) {
            futures.add(() async {
              await scope.resolveDependencyKey(descriptor.key, async: true);
            }());
          }
        }
      }
    }
    await Future.wait(futures);
  }

  List<DependencyDescriptor<dynamic>> _readinessDescriptors() {
    final descriptors =
        List<DependencyDescriptor<dynamic>>.of(_registry.values);
    for (final scope in _liveScopes) {
      if (!scope.isDisposed) {
        descriptors.addAll(scope.localDescriptors);
      }
    }
    return descriptors;
  }

  bool _countsForAllReady(DependencyDescriptor<dynamic> d) {
    if (d.isReady) return false;
    switch (d.lifecycle) {
      case DependencyLifecycle.asyncSingleton:
        return d.eagerAsync ||
            d.hasAsyncResolution ||
            d.signalsReady ||
            d.pendingResult != null;
      case DependencyLifecycle.asyncFactory:
      case DependencyLifecycle.factory:
        return false;
      case DependencyLifecycle.singleton:
      case DependencyLifecycle.lazySingleton:
        return d.signalsReady || d.pendingResult != null;
    }
  }

  /// Manually signals that a [signalsReady] registration is ready.
  ///
  /// When [instance] is provided, the matching cached instance is located in
  /// the active scope chain or root registry. When `null`, every pending
  /// manual readiness signal is completed.
  void signalReady([Object? instance]) {
    final scope = _activeScope;
    if (scope != null) {
      scope.signalReady(instance);
      return;
    }
    _signalReadyRoot(instance);
  }

  /// Root-registry signal used as the scope fallback target.
  void signalReadyFromRoot() {
    for (final descriptor in _registry.values) {
      if (descriptor.signalsReady && !descriptor.isReady) {
        descriptor.signalReady();
      }
    }
  }

  void _signalReadyRoot(Object? instance) {
    if (instance == null) {
      signalReadyFromRoot();
      return;
    }
    final descriptor = findDescriptorByInstanceFromRoot(instance);
    if (descriptor == null) {
      throw ArgumentError.value(
        instance,
        'instance',
        'No registered dependency owns this instance.',
      );
    }
    if (!descriptor.signalsReady) {
      throw ArgumentError.value(
        instance,
        'instance',
        'This instance is not registered with signalsReady: true.',
      );
    }
    if (descriptor.isReady) {
      throw StateError('This instance was already signalled ready.');
    }
    descriptor.signalReady();
  }

  DependencyDescriptor<dynamic> _requireDescriptor<T extends Object>(
      {String? instanceName}) {
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
    return descriptor;
  }

  // ---------------------------------------------------------------------------
  // RESET & CLEANUP
  // ---------------------------------------------------------------------------

  /// Clears the cached instance of a lazy singleton while keeping the
  /// registration alive, so the next resolution recreates it.
  ///
  /// Operates on the active scope when one is pushed, otherwise on the root
  /// registry. An optional [disposingFunction] overrides the registered
  /// `onDispose` for this reset.
  Future<void> resetLazySingleton<T extends Object>({
    String? instanceName,
    bool disposeHooks = true,
    FutureOr<void> Function(T instance)? disposingFunction,
  }) async {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.resetLazySingleton<T>(
        instanceName: instanceName,
        disposeHooks: disposeHooks,
        disposingFunction: disposingFunction,
      );
    }
    final descriptor = _requireDescriptor<T>(instanceName: instanceName);
    await descriptor.resetLazy(
      disposeHooks: disposeHooks,
      disposingFunction: disposingFunction == null
          ? null
          : (dynamic instance) => disposingFunction(instance as T),
    );
  }

  /// Resets every instantiated lazy singleton in the active scope (or the
  /// root registry when no scope is active).
  Future<void> resetLazySingletons({bool disposeHooks = true}) async {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.resetLazySingletons(disposeHooks: disposeHooks);
    }
    final targets = _registry.values
        .where((d) =>
            (d.lifecycle == DependencyLifecycle.lazySingleton ||
                d.lifecycle == DependencyLifecycle.asyncSingleton) &&
            (d.hasInstance || d.hasAsyncResolution))
        .toList();
    for (final descriptor in targets) {
      await descriptor.resetLazy(disposeHooks: disposeHooks);
    }
  }

  /// Clears all registrations in the current scope without popping it.
  ///
  /// When [disposeInstances] is true, cached instances and `onDispose` hooks
  /// run in reverse registration order.
  Future<void> resetScope({bool disposeInstances = true}) async {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      return scope.reset(disposeInstances: disposeInstances);
    }
    await _resetRootDependencies(disposeInstances: disposeInstances);
  }

  Future<void> _resetRootDependencies({required bool disposeInstances}) async {
    final descriptors = _registry.values.toList()
      ..sort((a, b) => b.registrationIndex.compareTo(a.registrationIndex));
    for (final descriptor in descriptors) {
      notifyDependencyEvent(DependencyChangeKind.unregistered, descriptor);
      if (disposeInstances) {
        await descriptor.dispose();
      }
    }
    _registry.clear();
    _registrationCounter = 0;
  }

  /// Unregisters and disposes the dependency of type [T].
  ///
  /// Operates on the active scope when one is pushed. Returns a [Future]
  /// that completes when asynchronous disposal hooks have finished. Missing
  /// registrations are silently ignored; pass `throwOnMissing: true` to get a
  /// [BridgeDependencyNotFoundException].
  Future<void> unregister<T extends Object>({
    String? instanceName,
    bool throwOnMissing = false,
  }) async {
    _ensureActive();
    final scope = _activeScope;
    if (scope != null) {
      if (!scope.isRegistered<T>(instanceName: instanceName)) {
        if (throwOnMissing) {
          throw BridgeDependencyNotFoundException(T,
              instanceName: instanceName);
        }
        return;
      }
      // Remove the registration from whichever scope owns it; registrations
      // that only exist on the root registry fall through to root removal.
      final key = DependencyKey(T, instanceName);
      var current = scope;
      while (true) {
        if (current.hasLocal(key)) {
          await current.unregister<T>(instanceName: instanceName);
          return;
        }
        final parent = current.parentScope;
        if (parent == null) break;
        current = parent;
      }
    }
    await _unregisterRootDependency<T>(
      instanceName: instanceName,
      throwOnMissing: throwOnMissing,
    );
  }

  Future<void> _unregisterRootDependency<T extends Object>({
    String? instanceName,
    required bool throwOnMissing,
  }) async {
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry.remove(key);
    if (descriptor == null) {
      if (throwOnMissing) {
        throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
      }
      return;
    }
    notifyDependencyEvent(DependencyChangeKind.unregistered, descriptor);
    await descriptor.dispose();
  }

  // ---------------------------------------------------------------------------
  // MODULE LIFECYCLE MANAGEMENT
  // ---------------------------------------------------------------------------

  /// Registers and initializes a single [FeatureModule].
  ///
  /// Validates dependencies, awaits [FeatureModule.registerDependencies]
  /// (which may be synchronous or asynchronous), and then triggers
  /// [FeatureModule.init]. If registration or initialization fails, the
  /// module's resources and dependencies are rolled back before the original
  /// error is rethrown.
  ///
  /// Module registrations may run concurrently: each module's dependencies
  /// are attributed to the correct owner via an async-local zone context.
  ///
  /// When [checkHealth] is true, [FeatureModule.healthCheck] runs right after
  /// successful registration; unhealthy results and thrown errors are
  /// reported via [reportBridgeError] without failing registration.
  Future<void> registerModule(
    FeatureModule module, {
    bool checkHealth = false,
  }) async {
    _ensureActive();
    final moduleName = module.name;
    if (_modules.containsKey(moduleName)) {
      throw BridgeModuleAlreadyRegisteredException(moduleName);
    }

    // Environment-gated modules are skipped silently when the active
    // environment is not in their allow-list.
    final environments = module.environments;
    if (environments != null && !environments.contains(_config.environment)) {
      return;
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
      // The zone value propagates across awaits inside registerDependencies
      // and init, attributing every registration to this module even when
      // multiple modules register concurrently.
      await runZoned(
        () async {
          await module.registerDependencies(this);
          _registrationDepth++;
          try {
            await module.init(this);
          } finally {
            _registrationDepth--;
          }
        },
        zoneValues: {_moduleOwnerZoneKey: moduleName},
      );
    } catch (_) {
      await _rollbackModuleRegistration(module);
      rethrow;
    }

    if (checkHealth) {
      await _runModuleHealthCheck(module);
    }

    if (_registrationDepth == 0) {
      _notifyModulesReadyIfNeeded();
    }
  }

  Future<void> _runModuleHealthCheck(FeatureModule module) async {
    try {
      final healthy = await module.healthCheck(this);
      if (!healthy) {
        reportBridgeError(
          StateError('healthCheck returned false'),
          StackTrace.current,
          context: 'Module health check for ${module.name}',
        );
      }
    } catch (error, stackTrace) {
      reportBridgeError(
        error,
        stackTrace,
        context: 'Module health check for ${module.name}',
      );
    }
  }

  /// Registers a callback invoked whenever all modules have been registered
  /// and initialized (the "modules ready" state).
  ///
  /// If modules are already registered when this is called, the callback is
  /// invoked immediately. The hook re-arms automatically when the last module
  /// is unregistered or [reset] is called, so callbacks fire again on the
  /// next registration cycle. Callback errors are reported via
  /// [reportBridgeError] and never break module registration.
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
          reportBridgeError(
            error,
            stackTrace,
            context: 'While running onModulesReady callback',
          );
        }));
      }
    } catch (error, stackTrace) {
      reportBridgeError(
        error,
        stackTrace,
        context: 'While running onModulesReady callback',
      );
    }
  }

  Future<void> _rollbackModuleRegistration(FeatureModule module) async {
    final moduleName = module.name;

    try {
      await module.dispose(this);
    } catch (error, stackTrace) {
      reportBridgeError(
        error,
        stackTrace,
        context:
            'While rolling back failed module registration for $moduleName',
      );
    }

    try {
      await _eventBus.cancelSubscriptionsForOwner(moduleName);
    } catch (error, stackTrace) {
      reportBridgeError(
        error,
        stackTrace,
        context: 'While canceling subscriptions for failed module $moduleName',
      );
    }

    await _removeModuleDependencies(moduleName);
    _modules.remove(moduleName);
  }

  Future<void> _removeModuleDependencies(String moduleName) async {
    // Module-owned dependencies may live in the root registry or in any live
    // scope when modules were registered while a scope was active.
    final rootKeys = _registry.entries
        .where((entry) => entry.value.ownerModuleName == moduleName)
        .map((entry) => entry.key)
        .toList();
    for (final key in rootKeys) {
      final descriptor = _registry.remove(key);
      if (descriptor != null) {
        notifyDependencyEvent(DependencyChangeKind.unregistered, descriptor);
        await descriptor.dispose();
      }
    }
    for (final scope in _liveScopes.toList()) {
      await scope.removeModuleDependencies(moduleName);
    }
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
  ///
  /// When [checkHealth] is true, each module's [FeatureModule.healthCheck]
  /// runs right after its successful registration; results are reported via
  /// [reportBridgeError] without failing the batch. See [registerModule].
  Future<void> registerModules(
    List<FeatureModule> modules, {
    bool checkHealth = false,
  }) async {
    _ensureActive();
    _registrationDepth++;
    try {
      for (final module in _topologicalSortModules(modules)) {
        await registerModule(module, checkHealth: checkHealth);
      }
    } finally {
      _registrationDepth--;
    }
    _notifyModulesReadyIfNeeded();
  }

  /// Orders [modules] so that every module is initialized after the modules
  /// it declares in [FeatureModule.dependencies].
  ///
  /// The sort is stable: modules without inter-dependencies keep their
  /// original order. Dependencies on modules outside the batch are ignored
  /// (they must already be registered). Throws a [StateError] when the batch
  /// contains a dependency cycle.
  List<FeatureModule> _topologicalSortModules(List<FeatureModule> modules) {
    final byType = <Type, FeatureModule>{};
    for (final module in modules) {
      byType[module.runtimeType] = module;
    }

    final sorted = <FeatureModule>[];
    final state = <FeatureModule, int>{}; // 0=unvisited,1=visiting,2=done

    void visit(FeatureModule module) {
      final mark = state[module];
      if (mark == 2) return;
      if (mark == 1) {
        throw StateError('Circular module dependency detected involving '
            '${module.name}.');
      }
      state[module] = 1;
      for (final depType in module.dependencies) {
        final dep = byType[depType];
        if (dep != null) visit(dep);
      }
      state[module] = 2;
      sorted.add(module);
    }

    for (final module in modules) {
      visit(module);
    }
    return sorted;
  }

  /// Runs [FeatureModule.healthCheck] on every registered module and returns
  /// one [ModuleHealthResult] per module, in registration order.
  ///
  /// Modules whose `environments` allow-list excludes the active environment
  /// are skipped during registration and therefore never appear here. Errors
  /// thrown by a health check are captured in the result's `error` field
  /// with `isHealthy: false` instead of propagating — inspect the returned
  /// list (or check `results.every((r) => r.isHealthy)`) to detect unhealthy
  /// modules.
  Future<List<ModuleHealthResult>> checkModuleHealth() async {
    _ensureActive();
    final results = <ModuleHealthResult>[];
    for (final module in _modules.values) {
      try {
        final healthy = await module.healthCheck(this);
        results.add(ModuleHealthResult(
          moduleName: module.name,
          isHealthy: healthy,
        ));
      } catch (error) {
        results.add(ModuleHealthResult(
          moduleName: module.name,
          isHealthy: false,
          error: error,
        ));
      }
    }
    return results;
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
    await _removeModuleDependencies(moduleName);

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

  /// Returns the most recently published event assignable to [T], or `null`.
  T? lastEvent<T extends BridgeEvent>() => _eventBus.lastEvent<T>();

  /// Returns a stream replaying up to the last 200 events of type [T] before
  /// continuing with live events.
  Stream<T> history<T extends BridgeEvent>() => _eventBus.history<T>();

  /// Completes with the next event of type [T], or throws a [TimeoutException]
  /// if [timeout] elapses first.
  Future<T> once<T extends BridgeEvent>({Duration? timeout}) =>
      _eventBus.once<T>(timeout: timeout);

  /// Whether at least one active managed subscription listens to events of
  /// type [T]. See [BridgeEventBus.hasListeners] for matching semantics.
  bool hasListeners<T extends BridgeEvent>() => _eventBus.hasListeners<T>();

  // ---------------------------------------------------------------------------
  // DIAGNOSTICS
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // DEVTOOLS SERVICE EXTENSION
  // ---------------------------------------------------------------------------

  static bool _devToolsRegistered = false;

  /// Registers VM service extensions for live container inspection.
  ///
  /// Available extensions (query via `dart:developer` / DevTools VM service):
  /// - `ext.modular_bridge.state` — JSON snapshot of registrations, scopes,
  ///   modules, pending async resolutions, leak issues, and metrics.
  /// - `ext.modular_bridge.graph` — Graphviz DOT of the `dependsOn` graph.
  /// - `ext.modular_bridge.metrics` — resolution metrics snapshot.
  ///
  /// Registration is process-wide: the first bridge to call this method owns
  /// the extensions. No-op on platforms without VM service support.
  void enableDevTools() {
    if (_devToolsRegistered) return;
    try {
      developer.registerExtension(
        'ext.modular_bridge.state',
        (method, params) async => developer.ServiceExtensionResponse.result(
            jsonEncode(_devToolsState())),
      );
      developer.registerExtension(
        'ext.modular_bridge.graph',
        (method, params) async => developer.ServiceExtensionResponse.result(
            jsonEncode({'dot': dependencyGraph().toDot()})),
      );
      developer.registerExtension(
        'ext.modular_bridge.metrics',
        (method, params) async => developer.ServiceExtensionResponse.result(
            jsonEncode(metrics.snapshot())),
      );
      _devToolsRegistered = true;
    } catch (error, stackTrace) {
      reportBridgeError(
        error,
        stackTrace,
        context: 'While registering DevTools service extensions',
      );
    }
  }

  Map<String, Object?> _devToolsState() {
    final report = diagnosticsReport();
    return {
      'registrations': [
        for (final info in report.registrations)
          {
            'key': info.key.toString(),
            'lifecycle': info.lifecycle.name,
            'scope': info.scopeName,
            'module': info.ownerModuleName,
            'isReady': info.isReady,
            'hasInstance': info.hasInstance,
            'signalsReady': info.signalsReady,
          },
      ],
      'modules': report.moduleNames,
      'scopes': report.activeScopeNames,
      'scopeStack': report.scopeStack,
      'pendingAsyncResolutions': report.pendingAsyncResolutions,
      'issues': report.issues,
      'metrics': metrics.snapshot(),
      'events': {
        'totalPublished': _eventBus.totalPublished,
        'publishCounts': {
          for (final e in _eventBus.publishCounts.entries)
            e.key.toString(): e.value,
        },
      },
    };
  }

  /// Returns a structured snapshot of container health for debugging and
  /// test assertions.
  BridgeDiagnosticsReport diagnosticsReport() {
    final registrations = <DependencyInfo>[
      ...dependencyInfo,
      for (final scope in _liveScopes)
        if (!scope.isDisposed) ...scope.dependencyInfo,
    ];
    return BridgeDiagnosticsReport(
      registrations: registrations,
      moduleNames: activeModuleNames,
      activeScopeNames: [
        for (final scope in _liveScopes)
          if (!scope.isDisposed)
            scope.scopeName ?? 'scope#${identityHashCode(scope)}',
      ],
      scopeStack: activeScopeNames,
      activeSubscriptionCount: _eventBus.activeSubscriptionCount,
      pendingAsyncResolutions: registrations
          .where((d) => d.hasAsyncResolution && !d.isReady)
          .map((d) => d.key.toString())
          .toList(growable: false),
      issues: debugLeakReport(),
      metrics: metrics.snapshot(),
    );
  }

  /// Builds the `dependsOn` dependency graph across the root registry and
  /// all live scopes, including cycle detection.
  ///
  /// Edges point from a registration to each dependency it waits on. A
  /// dependency key is matched to nodes registered in the same scope first,
  /// then to root registrations — mirroring resolution fallback.
  BridgeDependencyGraph dependencyGraph() {
    final infos = <DependencyInfo>[
      ...dependencyInfo,
      for (final scope in _liveScopes)
        if (!scope.isDisposed) ...scope.dependencyInfo,
    ];

    // Index nodes by key; prefer same-scope matches during edge resolution.
    final byKey = <DependencyKey, List<DependencyInfo>>{};
    for (final info in infos) {
      byKey.putIfAbsent(info.key, () => []).add(info);
    }

    DependencyInfo? resolveTarget(DependencyInfo from, DependencyKey dep) {
      final candidates = byKey[dep];
      if (candidates == null || candidates.isEmpty) return null;
      for (final c in candidates) {
        if (c.scopeName == from.scopeName) return c;
      }
      for (final c in candidates) {
        if (c.scopeName == null) return c;
      }
      return candidates.first;
    }

    final edges = <DependencyEdge>[];
    final adjacency = <String, List<String>>{};
    for (final info in infos) {
      final fromId = BridgeDependencyGraph.nodeId(info);
      for (final dep in info.dependsOn) {
        final target = resolveTarget(info, dep);
        edges.add(DependencyEdge(
          from: info,
          to: dep,
          toNodeId:
              target == null ? null : BridgeDependencyGraph.nodeId(target),
        ));
        if (target != null) {
          adjacency
              .putIfAbsent(fromId, () => [])
              .add(BridgeDependencyGraph.nodeId(target));
        }
      }
    }

    // Iterative DFS cycle detection.
    final cycles = <List<String>>[];
    final visited = <String>{};
    final stack = <String>[];
    final onStack = <String>{};

    void visit(String node) {
      if (onStack.contains(node)) {
        final start = stack.indexOf(node);
        cycles.add([...stack.sublist(start), node]);
        return;
      }
      if (visited.contains(node)) return;
      visited.add(node);
      onStack.add(node);
      stack.add(node);
      for (final next in adjacency[node] ?? const <String>[]) {
        visit(next);
      }
      stack.removeLast();
      onStack.remove(node);
    }

    for (final info in infos) {
      visit(BridgeDependencyGraph.nodeId(info));
    }

    return BridgeDependencyGraph(
      nodes: infos,
      edges: edges,
      cycles: cycles,
    );
  }

  /// Returns a list of detected leak/integrity issues in the container.
  ///
  /// Intended for test verification after [reset] or module teardown.
  /// An empty list means no issues were detected. Note that active event bus
  /// subscriptions are reported but may be intentional while modules are
  /// registered.
  @visibleForTesting()
  List<String> debugLeakReport() {
    final issues = <String>[];

    if (currentResolutionChain.isNotEmpty) {
      issues.add(
        'Dependency resolution chain is not empty: '
        '${currentResolutionChain.map((f) => f.key.toString()).join(' -> ')}',
      );
    }

    final activeSubscriptions = _eventBus.activeSubscriptionCount;
    if (activeSubscriptions > 0) {
      issues.add('$activeSubscriptions active event bus subscription(s)');
    }

    return issues;
  }

  // ---------------------------------------------------------------------------
  // TEST HELPERS
  // ---------------------------------------------------------------------------

  /// Throws a [StateError] unless a dependency of type [T] is registered in
  /// the current resolution context.
  @visibleForTesting()
  void assertRegistered<T extends Object>({String? instanceName}) {
    if (!isRegistered<T>(instanceName: instanceName)) {
      throw StateError(
          'Expected dependency $T${instanceName == null ? '' : ' ($instanceName)'} '
          'to be registered, but it is not.');
    }
  }

  /// Registration keys that still participate in readiness tracking and are
  /// not ready yet.
  @visibleForTesting()
  List<String> get pendingReadinessKeys => _readinessDescriptors()
      .where((d) => _countsForAllReady(d) && !d.isReady)
      .map((d) => d.key.toString())
      .toList(growable: false);

  /// Throws a [StateError] listing pending registrations unless
  /// [allReadySync] returns true.
  @visibleForTesting()
  void assertAllReadySync() {
    if (!allReadySync()) {
      throw StateError(
          'Expected all readiness-tracked dependencies to be ready, but '
          'these are still pending: ${pendingReadinessKeys.join(', ')}.');
    }
  }

  /// Throws a [StateError] if [debugLeakReport] detects any issues.
  @visibleForTesting()
  void assertNoLeaks() {
    final issues = debugLeakReport();
    if (issues.isNotEmpty) {
      throw StateError('ModularBridge leak/integrity issues detected:\n'
          '${issues.map((i) => ' - $i').join('\n')}');
    }
  }

  /// Completely resets the container.
  ///
  /// Disposes all registered singletons (waiting for in-flight async
  /// resolutions), unregisters modules, cancels event subscriptions, and
  /// clears the resolution state. Ideal for test `tearDown`.
  ///
  /// When [disposeInstances] is false, registrations are dropped without
  /// running cached instances or `onDispose` hooks. Module `dispose` hooks and
  /// event subscription cleanup always run.
  Future<void> reset({bool disposeInstances = true}) async {
    _registrationDepth = 0;
    _configBindings.clear();

    // Dispose scopes in reverse stack order, then any remaining live scopes.
    while (_scopeStack.isNotEmpty) {
      final scope = _scopeStack.removeLast();
      try {
        await scope.dispose(disposeInstances: disposeInstances);
      } finally {
        _notifyScopeChanged(false);
      }
    }
    for (final scope in _liveScopes.toList().reversed) {
      await scope.dispose(disposeInstances: disposeInstances);
    }

    // Dispose modules in reverse order
    final moduleList = _modules.values.toList().reversed;
    for (final module in moduleList) {
      try {
        await module.dispose(this);
      } catch (e, st) {
        reportBridgeError(
          e,
          st,
          context: 'While disposing module ${module.name}',
        );
      }
    }
    _modules.clear();
    _modulesReadyNotified = false;

    // Dispose dependencies in reverse registration order (LIFO)
    await _resetRootDependencies(disposeInstances: disposeInstances);

    // Clear event bus subscriptions
    await _eventBus.clearSubscriptions();
  }

  /// Disposes the container: resets all state and closes the config change
  /// stream. The event bus and the injected [BridgeConfig] are **not**
  /// disposed — they may be shared or owned elsewhere; dispose them
  /// separately if needed.
  ///
  /// After [dispose], registrations and resolutions throw a [StateError].
  /// Calling [dispose] more than once is a no-op. Use [reset] instead when
  /// the container should remain usable (e.g. between tests).
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await reset();
    await _configValueSubscription.cancel();
    await _configSwapSubscription.cancel();
    await _configController.close();
    await _dependencyEvents.close();
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw StateError('Cannot use a disposed ModularBridge.');
    }
  }
}

/// Immutable diagnostics snapshot for a [ModularBridge] container.
@immutable()
final class BridgeDiagnosticsReport {
  /// Creates a diagnostics report.
  const BridgeDiagnosticsReport({
    required this.registrations,
    required this.moduleNames,
    required this.activeScopeNames,
    required this.scopeStack,
    required this.activeSubscriptionCount,
    required this.pendingAsyncResolutions,
    required this.issues,
    required this.metrics,
  });

  /// All known dependency registrations across root and live scopes.
  final List<DependencyInfo> registrations;

  /// Registered feature module names.
  final List<String> moduleNames;

  /// Names of all live scopes (explicit and stacked).
  final List<String> activeScopeNames;

  /// Names of scopes on the active resolution stack, bottom to top.
  final List<String> scopeStack;

  /// Active event bus subscription count.
  final int activeSubscriptionCount;

  /// Dependency keys with in-flight or incomplete async resolutions.
  final List<String> pendingAsyncResolutions;

  /// Leak/integrity issues detected by [ModularBridge.debugLeakReport].
  final List<String> issues;

  /// Resolution metrics snapshot (`DependencyMetrics.snapshot()`).
  final Map<String, Object?> metrics;

  /// Whether the report contains no detected issues.
  bool get isHealthy => issues.isEmpty;

  @override
  String toString() =>
      'BridgeDiagnosticsReport(registrations: ${registrations.length}, '
      'modules: ${moduleNames.length}, scopes: ${activeScopeNames.length}, '
      'pendingAsync: ${pendingAsyncResolutions.length}, issues: $issues)';
}
