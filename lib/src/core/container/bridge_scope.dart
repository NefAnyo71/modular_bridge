import 'dart:async';

import '../annotations.dart';
import '../errors/bridge_error_reporter.dart';
import '../exceptions/bridge_exceptions.dart';
import 'dependency_descriptor.dart';
import 'dependency_event.dart';
import 'modular_bridge_container.dart';
import 'resolution_context.dart';

/// A named dependency scope for request/session-scoped registrations.
///
/// Dependencies registered on a scope are resolved **only** through the scope
/// itself (`scope.get<T>()`); they are invisible to sibling scopes. Scopes form
/// a hierarchy: a scope created via [createChildScope] or pushed through
/// [ModularBridge.pushNewScope] resolves unregistered types through its parent
/// scope, falling back to the root [ModularBridge].
///
/// ```text
/// ModularBridge
///   └── BridgeScope (session)
///         └── BridgeScope (request)   ← resolves request → session → bridge
/// ```
///
/// Call [dispose] when the scope ends; every dependency owned by the scope —
/// including child scopes — is disposed and its `onDispose` hooks run.
final class BridgeScope {
  /// Creates a scope bound to the root [bridge] container.
  ///
  /// Prefer [ModularBridge.createScope] or [ModularBridge.pushNewScope] for
  /// discoverability. Use [createChildScope] to build hierarchical scopes.
  BridgeScope(
    this.bridge, {
    BridgeScope? parent,
    this.scopeName,
    this.onDisposeCallback,
  }) : _parent = parent {
    // Scope names must be unique across every live scope so that
    // dropScope/popScopesTill/findScope resolve unambiguously. Validate
    // before mutating the parent/bridge so a rejected name leaves no trace.
    bridge.checkScopeNameAvailable(scopeName);
    parent?._children.add(this);
    bridge.trackScope(this);
  }

  /// The root container this scope hierarchy is bound to.
  final ModularBridge bridge;

  /// Optional name used by [ModularBridge.dropScope] and
  /// [ModularBridge.popScopesTill].
  ///
  /// Names must be unique across every live scope on the same bridge —
  /// creating a scope whose name is already taken throws a [StateError].
  /// The name is freed once the scope is disposed or popped.
  final String? scopeName;

  /// Convenience alias for [scopeName].
  String? get name => scopeName;

  /// Optional callback invoked when this scope is disposed or popped.
  final FutureOr<void> Function()? onDisposeCallback;

  final BridgeScope? _parent;
  final List<BridgeScope> _children = [];
  final Map<DependencyKey, DependencyDescriptor<dynamic>> _registry = {};
  final Map<String, dynamic> _configOverrides = {};
  // key → the shadowing instance that triggered onGetShadowed. Stored at
  // notify time because transient factories and async factories never populate
  // cachedInstance, which onLeaveShadow still needs.
  final Map<DependencyKey, Object?> _shadowInstances = {};
  int _registrationCounter = 0;
  bool _isDisposed = false;
  bool _isFinal = false;

  /// Whether [dispose] has been called on this scope.
  bool get isDisposed => _isDisposed;

  /// Whether this scope has been sealed against further registrations.
  bool get isFinal => _isFinal;

  /// The parent scope in the hierarchy, or `null` for a root scope whose
  /// fallback is [bridge] itself.
  BridgeScope? get parentScope => _parent;

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot use a disposed BridgeScope.');
    }
  }

  void _ensureCanRegister() {
    _ensureNotDisposed();
    if (_isFinal) {
      throw StateError(
          'Cannot register on a finalized BridgeScope. Register dependencies '
          'inside createScopeAsync(init:) or before sealing the scope.');
    }
  }

  /// Creates a child scope whose unregistered lookups fall back to this scope.
  BridgeScope createChildScope({String? scopeName}) {
    _ensureCanRegister();
    return BridgeScope(bridge, parent: this, scopeName: scopeName);
  }

  // ---------------------------------------------------------------------------
  // SCOPED CONFIG OVERRIDES
  // ---------------------------------------------------------------------------

  /// Sets a scope-local configuration override for [key].
  ///
  /// The override shadows the global [BridgeConfig] value for every
  /// [configValue] lookup and config-bound dependency resolved through this
  /// scope (or its descendants). Changing an override re-decodes that scope's
  /// config-bound dependencies on next resolution.
  ///
  /// Overrides live and die with the scope — disposing the scope removes them.
  void setConfigValue(String key, dynamic value) {
    _ensureNotDisposed();
    _configOverrides[key] = value;
    bridge.notifyScopeConfigBindings(this);
  }

  /// Removes a scope-local override previously set via [setConfigValue].
  ///
  /// Returns `true` when an override existed. Config-bound dependencies of
  /// this scope are re-decoded on next resolution.
  bool removeConfigValue(String key) {
    _ensureNotDisposed();
    if (!_configOverrides.containsKey(key)) return false;
    _configOverrides.remove(key);
    bridge.notifyScopeConfigBindings(this);
    return true;
  }

  /// Whether this scope (not its ancestors) currently overrides [key].
  bool hasConfigOverride(String key) => _configOverrides.containsKey(key);

  /// Unmodifiable view of this scope's own config overrides.
  Map<String, dynamic> get configOverrides =>
      Map<String, dynamic>.unmodifiable(_configOverrides);

  /// Reads a configuration value with scope overrides applied.
  ///
  /// Lookup order: this scope's overrides, then ancestor scopes'
  /// overrides, then the global [BridgeConfig]. Mirrors
  /// [BridgeConfig.get] semantics — throws
  /// [BridgeConfigKeyNotFoundException] when the key is absent and no
  /// [defaultValue] is given, and [BridgeConfigTypeMismatchException] on a
  /// type mismatch.
  T configValue<T>(String key, {T? defaultValue}) {
    if (_configOverrides.containsKey(key)) {
      final value = _configOverrides[key];
      if (value is T) return value;
      throw BridgeConfigTypeMismatchException(
        key: key,
        expectedType: T,
        actualType: value.runtimeType,
      );
    }
    final parent = _parent;
    if (parent != null) {
      return parent.configValue<T>(key, defaultValue: defaultValue);
    }
    return bridge.config.get<T>(key, defaultValue: defaultValue);
  }

  /// Prevents further registrations on this scope after [init] completes.
  ///
  /// Used by [ModularBridge.createScopeAsync] and
  /// [ModularBridge.pushNewScope] with `isFinal: true`.
  void seal() {
    _isFinal = true;
  }

  // ---------------------------------------------------------------------------
  // REGISTRATION
  // ---------------------------------------------------------------------------

  void _register<T>(
    DependencyLifecycle lifecycle, {
    required DependencyKey key,
    T Function()? factory,
    Future<T> Function()? asyncFactory,
    T? instance,
    required bool override,
    FutureOr<void> Function(T instance)? onDispose,
    bool eagerAsync = false,
    bool signalsReady = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
    T Function(Object? param1, Object? param2)? paramFactory,
    Future<T> Function(Object? param1, Object? param2)? paramAsyncFactory,
    bool paramCached = false,
  }) {
    _ensureCanRegister();
    final existing = _registry[key];
    if (existing != null) {
      if (!override && !bridge.allowReassignment) {
        throw BridgeDependencyAlreadyRegisteredException(T,
            instanceName: key.name);
      }
      // Fire-and-forget for the same reason as ModularBridge._register:
      // registration is synchronous, so the old instance's disposal may
      // overlap the replacement's first resolution.
      unawaited(
          existing.dispose().catchError((Object error, StackTrace stackTrace) {
        reportBridgeError(
          error,
          stackTrace,
          context: 'While disposing replaced dependency ${key.toString()}',
        );
      }));
    }
    final descriptor = DependencyDescriptor<T>(
      key: key,
      lifecycle: lifecycle,
      registrationIndex: _registrationCounter++,
      factory: factory,
      asyncFactory: asyncFactory,
      instance: instance,
      onDispose: onDispose,
      eagerAsync: eagerAsync,
      signalsReady: signalsReady,
      dependsOn: List.unmodifiable(dependsOn),
      onCreated: onCreated,
      scopeName: scopeName,
      ownerModuleName: bridge.currentModuleOwnerForScope,
      paramFactory: paramFactory,
      paramAsyncFactory: paramAsyncFactory,
      paramCached: paramCached,
      metrics: bridge.metrics,
    );
    _registry[key] = descriptor;
    bridge.notifyDependencyEvent(DependencyChangeKind.registered, descriptor);
  }

  /// Registers an existing [instance] as an eager singleton within this scope.
  void registerSingleton<T extends Object>(
    T instance, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
    bool? signalsReady,
    void Function(T instance)? onCreated,
  }) {
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

  /// Registers a lazy singleton within this scope, instantiated on first resolution.
  void registerLazySingleton<T extends Object>(
    T Function() factory, {
    String? instanceName,
    bool override = false,
    void Function(T instance)? onDispose,
    bool signalsReady = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
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
  /// The factory receives this scope so it can resolve dependencies with the
  /// correct hierarchy. Resolution is triggered immediately.
  void registerSingletonWithDependencies<T extends Object>({
    required T Function(BridgeScope scope) factoryFunc,
    required Iterable<DependencyKey> dependsOn,
    String? instanceName,
    bool override = false,
    bool signalsReady = false,
    void Function(T instance)? onDispose,
    void Function(T instance)? onCreated,
  }) {
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
    // See ModularBridge.registerSingletonWithDependencies: the cleanup
    // chain must swallow resolution errors (surfaced via pendingResult)
    // instead of producing an unhandled async error.
    unawaited(pending.then<void>((_) {}, onError: (_, __) {}).whenComplete(() {
      if (identical(descriptor?.pendingResult, pending)) {
        descriptor?.pendingResult = null;
      }
    }));
  }

  /// Async variant of [registerSingletonWithDependencies].
  ///
  /// [factoryFunc] receives this scope and may return a value or a [Future];
  /// it runs only after every [dependsOn] key has resolved. Resolve the
  /// registration with [getAsync].
  void registerSingletonWithDependenciesAsync<T extends Object>({
    required FutureOr<T> Function(BridgeScope scope) factoryFunc,
    required Iterable<DependencyKey> dependsOn,
    String? instanceName,
    bool override = false,
    bool signalsReady = false,
    void Function(T instance)? onDispose,
    void Function(T instance)? onCreated,
  }) {
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
    // See ModularBridge.registerSingletonWithDependencies: the cleanup
    // chain must swallow resolution errors (surfaced via pendingResult)
    // instead of producing an unhandled async error.
    unawaited(pending.then<void>((_) {}, onError: (_, __) {}).whenComplete(() {
      if (identical(descriptor?.pendingResult, pending)) {
        descriptor?.pendingResult = null;
      }
    }));
  }

  /// Registers a transient factory within this scope.
  void registerFactory<T extends Object>(
    T Function() factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
    _register<T>(
      DependencyLifecycle.factory,
      key: DependencyKey(T, instanceName),
      factory: factory,
      override: override,
      dependsOn: dependsOn,
      onCreated: onCreated,
    );
  }

  /// Registers an asynchronous singleton within this scope.
  ///
  /// Resolved with [getAsync]; concurrent calls share a single in-flight
  /// resolution and failures are retried on the next call.
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

  /// Registers a lazy asynchronous singleton within this scope.
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

  /// Registers an eager asynchronous singleton within this scope.
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

  /// Registers an asynchronous transient factory within this scope.
  ///
  /// Every [getAsync] call produces a new instance.
  void registerFactoryAsync<T extends Object>(
    Future<T> Function() factory, {
    String? instanceName,
    bool override = false,
    Iterable<DependencyKey> dependsOn = const [],
    void Function(T instance)? onCreated,
  }) {
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
    _ensureNotDisposed();
    final key = DependencyKey(T, instanceName);
    final descriptor = _localDescriptor(key);
    if (descriptor == null) {
      final parent = _parent;
      if (parent != null) {
        return parent.getParam<T, P1, P2>(
          param1: param1,
          param2: param2,
          instanceName: instanceName,
        );
      }
      return bridge.getParamFromRoot<T, P1, P2>(
        param1: param1,
        param2: param2,
        instanceName: instanceName,
      );
    }
    return _resolveDescriptorSyncParam<T, P1, P2>(
        key, descriptor, param1, param2);
  }

  /// Asynchronously resolves a parameterized factory registered via
  /// [registerFactoryParamAsync]/[registerCachedFactoryParamAsync].
  ///
  /// Also works for synchronous parameter factories.
  Future<T> getParamAsync<T extends Object, P1, P2>({
    required P1 param1,
    required P2 param2,
    String? instanceName,
  }) {
    _ensureNotDisposed();
    final key = DependencyKey(T, instanceName);
    final descriptor = _localDescriptor(key);
    if (descriptor == null) {
      final parent = _parent;
      if (parent != null) {
        return parent.getParamAsync<T, P1, P2>(
          param1: param1,
          param2: param2,
          instanceName: instanceName,
        );
      }
      return bridge.getParamAsyncFromRoot<T, P1, P2>(
        param1: param1,
        param2: param2,
        instanceName: instanceName,
      );
    }
    return _resolveDescriptorAsyncParam<T, P1, P2>(
        key, descriptor, param1, param2);
  }

  T _resolveDescriptorSyncParam<T, P1, P2>(
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

  Future<T> _resolveDescriptorAsyncParam<T, P1, P2>(
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

  /// Replaces an existing scope-local dependency with [instance].
  ///
  /// If the dependency is not registered on this scope it is added as a
  /// singleton; parent registrations are never touched.
  void override<T extends Object>(T instance, {String? instanceName}) {
    registerSingleton<T>(instance, instanceName: instanceName, override: true);
  }

  /// Test helper: replaces [T] with an async singleton resolved lazily on
  /// the first [getAsync] call.
  void overrideAsync<T extends Object>(
    Future<T> Function() factory, {
    String? instanceName,
  }) {
    registerAsyncSingleton<T>(
      factory,
      instanceName: instanceName,
      override: true,
    );
  }

  /// Test helper: replaces [T] with a transient factory producing a new
  /// instance per resolution.
  void overrideFactory<T extends Object>(
    T Function() factory, {
    String? instanceName,
  }) {
    registerFactory<T>(
      factory,
      instanceName: instanceName,
      override: true,
    );
  }

  // ---------------------------------------------------------------------------
  // RESOLUTION
  // ---------------------------------------------------------------------------

  /// Finds the descriptor for [key] registered directly on this scope.
  DependencyDescriptor<dynamic>? _localDescriptor(DependencyKey key) =>
      _registry[key];

  /// Whether [key] is registered directly on this scope.
  bool hasLocal(DependencyKey key) => _registry.containsKey(key);

  /// Local registration descriptors on this scope (internal diagnostics use).
  List<DependencyDescriptor<dynamic>> get localDescriptors =>
      List.unmodifiable(_registry.values);

  /// Removes and disposes dependencies owned by [moduleName] directly on this
  /// scope. Used for module rollback when modules registered while a scope
  /// was active.
  Future<void> removeModuleDependencies(String moduleName) async {
    final keys = _registry.entries
        .where((entry) => entry.value.ownerModuleName == moduleName)
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      final descriptor = _registry.remove(key);
      if (descriptor != null) {
        bridge.notifyDependencyEvent(
            DependencyChangeKind.unregistered, descriptor);
        await descriptor.dispose();
      }
    }
  }

  /// Resolves a dependency identified by [key] through this scope hierarchy.
  ///
  /// Internal resolver used for `dependsOn` orchestration; returns a [Future]
  /// only when [async] is true.
  FutureOr<Object?> resolveDependencyKey(
    DependencyKey key, {
    required bool async,
  }) {
    final descriptor = _localDescriptor(key);
    if (descriptor == null) {
      final parent = _parent;
      if (parent != null) {
        return parent.resolveDependencyKey(key, async: async);
      }
      return bridge.resolveDependencyKeyFromRoot(key, async: async);
    }
    return _resolveDescriptor(key, descriptor, async: async);
  }

  Object? _resolveDescriptorSync(DependencyDescriptor<dynamic> descriptor) {
    if (descriptor.lifecycle == DependencyLifecycle.asyncSingleton ||
        descriptor.lifecycle == DependencyLifecycle.asyncFactory) {
      throw BridgeAsyncDependencyException(descriptor.key.type);
    }
    if (descriptor.isFrameFreeResolution) {
      return descriptor.resolve();
    }
    return resolveWithFrame(this, descriptor.key, () {
      _resolveDependsOnSync(descriptor);
      return descriptor.resolve();
    });
  }

  Future<Object?> _resolveDescriptorAsync(
      DependencyDescriptor<dynamic> descriptor) {
    if (descriptor.isFrameFreeResolution) {
      return descriptor.resolveAsync();
    }
    return resolveWithFrameAsync(this, descriptor.key, () async {
      await _resolveDependsOnAsync(descriptor);
      if (descriptor.lifecycle != DependencyLifecycle.asyncSingleton &&
          descriptor.lifecycle != DependencyLifecycle.asyncFactory) {
        return descriptor.resolve();
      }
      return descriptor.resolveAsync();
    });
  }

  FutureOr<Object?> _resolveDescriptor(
    DependencyKey key,
    DependencyDescriptor<dynamic> descriptor, {
    required bool async,
  }) {
    if (async) {
      return _resolveDescriptorAsync(descriptor);
    }
    return _resolveDescriptorSync(descriptor);
  }

  void _resolveDependsOnSync(DependencyDescriptor<dynamic> descriptor) {
    for (final dep in descriptor.dependsOn) {
      final result = resolveDependencyKey(dep, async: false);
      if (result is Future<Object?>) {
        throw BridgeAsyncDependencyException(dep.type);
      }
    }
  }

  Future<void> _resolveDependsOnAsync(
      DependencyDescriptor<dynamic> descriptor) async {
    for (final dep in descriptor.dependsOn) {
      await resolveDependencyKey(dep, async: true);
    }
  }

  /// Resolves an instance of type [T] from this scope, falling back through
  /// parent scopes to the root [ModularBridge] when [T] is not registered
  /// on this scope.
  T get<T extends Object>({String? instanceName}) {
    _ensureNotDisposed();
    final key = DependencyKey(T, instanceName);
    final descriptor = _localDescriptor(key);

    if (descriptor == null) {
      final parent = _parent;
      if (parent != null) {
        return parent.get<T>(instanceName: instanceName);
      }
      return bridge.getFromRoot<T>(instanceName: instanceName);
    }

    final instance = _resolveDescriptorSync(descriptor) as T;
    _notifyShadowed(key, instance);
    return instance;
  }

  /// Asynchronously resolves an instance of type [T] from this scope,
  /// falling back through parent scopes to the root [ModularBridge].
  ///
  /// Synchronous lifecycles resolve immediately; async lifecycles share a
  /// single in-flight resolution and participate in circular detection.
  Future<T> getAsync<T extends Object>({String? instanceName}) {
    _ensureNotDisposed();
    final key = DependencyKey(T, instanceName);
    final descriptor = _localDescriptor(key);

    if (descriptor == null) {
      final parent = _parent;
      if (parent != null) {
        return parent.getAsync<T>(instanceName: instanceName);
      }
      return bridge.getAsyncFromRoot<T>(instanceName: instanceName);
    }

    return _resolveDescriptorAsync(descriptor).then((value) {
      final instance = value as T;
      _notifyShadowed(key, instance);
      return instance;
    });
  }

  /// Resolves every registration of type [T] visible from this scope —
  /// including named instances — in nearest-scope-first order.
  ///
  /// When multiple scopes register the same key, only the nearest
  /// registration is resolved.
  List<T> getAll<T extends Object>() {
    _ensureNotDisposed();
    final keys = _visibleKeysForType<T>();
    return keys.map((key) => get<T>(instanceName: key.name)).toList();
  }

  /// Asynchronously resolves every registration of type [T] visible from
  /// this scope.
  Future<List<T>> getAllAsync<T extends Object>() async {
    _ensureNotDisposed();
    final keys = _visibleKeysForType<T>();
    return Future.wait(keys.map((key) => getAsync<T>(instanceName: key.name)));
  }

  List<DependencyKey> _visibleKeysForType<T extends Object>() {
    final keys = <DependencyKey>[];
    final seen = <DependencyKey>{};
    var scope = this;
    while (true) {
      for (final key in scope._registry.keys) {
        if (key.type == T && seen.add(key)) keys.add(key);
      }
      final parent = scope._parent;
      if (parent == null) break;
      scope = parent;
    }
    for (final key in bridge.registeredDependencies) {
      if (key.type == T && seen.add(key)) keys.add(key);
    }
    return keys;
  }

  /// Callable syntax shortcut for [get].
  T call<T extends Object>({String? instanceName}) =>
      get<T>(instanceName: instanceName);

  /// Attempts to resolve [T] from this scope or its ancestors.
  T? tryGet<T extends Object>({String? instanceName}) {
    if (isRegistered<T>(instanceName: instanceName)) {
      return get<T>(instanceName: instanceName);
    }
    return null;
  }

  /// Attempts to asynchronously resolve [T] from this scope or its ancestors.
  Future<T?> tryGetAsync<T extends Object>({String? instanceName}) async {
    if (!isRegistered<T>(instanceName: instanceName)) return null;
    return getAsync<T>(instanceName: instanceName);
  }

  /// Checks whether [T] is registered on this scope or any ancestor.
  bool isRegistered<T extends Object>({String? instanceName}) {
    final key = DependencyKey(T, instanceName);
    var scope = this;
    while (true) {
      if (scope._localDescriptor(key) != null) return true;
      final parent = scope._parent;
      if (parent == null) {
        return bridge.isRegisteredFromRoot<T>(instanceName: instanceName);
      }
      scope = parent;
    }
  }

  /// Returns `true` when [T] has no pending asynchronous resolution on this
  /// scope or its ancestors.
  bool isReadySync<T extends Object>({String? instanceName}) {
    final key = DependencyKey(T, instanceName);
    final descriptor = _findDescriptor(key);
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
    return descriptor.isReady;
  }

  /// Returns a [Future] that completes when [T] is ready for synchronous
  /// use, delegating through parent scopes to the root [ModularBridge].
  Future<void> isReady<T extends Object>({
    String? instanceName,
    Duration? timeout,
  }) {
    final key = DependencyKey(T, instanceName);
    final descriptor = _findDescriptor(key);
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
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
          pending: descriptor.isReady ? const [] : [key.toString()],
          ready: descriptor.isReady ? [key.toString()] : const [],
        ),
      );
    }
    return ready;
  }

  /// Finds the nearest registration below this scope for [key], used by
  /// [ShadowChangeHandlers] notifications.
  DependencyDescriptor<dynamic>? _findShadowedDescriptor(DependencyKey key) {
    var scope = _parent;
    while (scope != null) {
      final descriptor = scope._localDescriptor(key);
      if (descriptor != null) return descriptor;
      scope = scope._parent;
    }
    return bridge.findDescriptorFromRoot(key);
  }

  void _notifyShadowed(DependencyKey key, Object? instance) {
    if (instance == null || _shadowInstances.containsKey(key)) return;
    final target = _findShadowedDescriptor(key)?.cachedInstance;
    if (target is ShadowChangeHandlers) {
      _shadowInstances[key] = instance;
      try {
        target.onGetShadowed(instance);
      } catch (error, stackTrace) {
        reportBridgeError(
          error,
          stackTrace,
          context: 'While running ShadowChangeHandlers.onGetShadowed',
        );
      }
    }
  }

  void _releaseShadowNotifications() {
    for (final entry in _shadowInstances.entries) {
      final shadowed = _findShadowedDescriptor(entry.key)?.cachedInstance;
      if (shadowed is ShadowChangeHandlers) {
        try {
          shadowed.onLeaveShadow(entry.value);
        } catch (error, stackTrace) {
          reportBridgeError(
            error,
            stackTrace,
            context: 'While running ShadowChangeHandlers.onLeaveShadow',
          );
        }
      }
    }
    _shadowInstances.clear();
  }

  DependencyDescriptor<dynamic>? _findDescriptor(DependencyKey key) {
    var scope = this;
    while (true) {
      final descriptor = scope._localDescriptor(key);
      if (descriptor != null) return descriptor;
      final parent = scope._parent;
      if (parent == null) {
        return bridge.findDescriptorFromRoot(key);
      }
      scope = parent;
    }
  }

  // ---------------------------------------------------------------------------
  // RESET & READINESS
  // ---------------------------------------------------------------------------

  /// Clears the cached instance of a lazy singleton registered on this scope,
  /// keeping the registration alive so the next resolution recreates it.
  Future<void> resetLazySingleton<T extends Object>({
    String? instanceName,
    bool disposeHooks = true,
    FutureOr<void> Function(T instance)? disposingFunction,
  }) async {
    _ensureNotDisposed();
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry[key];
    if (descriptor == null) {
      throw BridgeDependencyNotFoundException(T, instanceName: instanceName);
    }
    await descriptor.resetLazy(
      disposeHooks: disposeHooks,
      disposingFunction: disposingFunction == null
          ? null
          : (dynamic instance) => disposingFunction(instance as T),
    );
  }

  /// Resets every instantiated lazy singleton registered directly on this
  /// scope. Registrations remain active; only cached instances are cleared.
  Future<void> resetLazySingletons({bool disposeHooks = true}) async {
    _ensureNotDisposed();
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

  /// Clears all registrations made directly on this scope.
  ///
  /// When [disposeInstances] is true, cached instances and `onDispose` hooks
  /// run in reverse registration order; when false the registrations are
  /// dropped without invoking disposal hooks.
  Future<void> reset({bool disposeInstances = true}) async {
    _ensureNotDisposed();
    _releaseShadowNotifications();
    final descriptors = _registry.values.toList()
      ..sort((a, b) => b.registrationIndex.compareTo(a.registrationIndex));
    for (final descriptor in descriptors) {
      bridge.notifyDependencyEvent(
          DependencyChangeKind.unregistered, descriptor);
      if (disposeInstances) {
        await descriptor.dispose();
      }
    }
    _registry.clear();
    _registrationCounter = 0;
  }

  /// Manually signals that a [signalsReady] registration is ready.
  ///
  /// When [instance] is provided, the matching cached instance is located in
  /// this scope or its ancestors. When `null`, every pending manual readiness
  /// signal in this scope hierarchy is completed.
  void signalReady([Object? instance]) {
    if (instance == null) {
      _signalAllReadyInHierarchy();
      return;
    }
    final descriptor = _findDescriptorByInstance(instance);
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

  void _signalAllReadyInHierarchy() {
    var scope = this;
    while (true) {
      for (final descriptor in scope._registry.values) {
        if (descriptor.signalsReady && !descriptor.isReady) {
          descriptor.signalReady();
        }
      }
      final parent = scope._parent;
      if (parent == null) {
        bridge.signalReadyFromRoot();
        return;
      }
      scope = parent;
    }
  }

  DependencyDescriptor<dynamic>? _findDescriptorByInstance(Object instance) {
    var scope = this;
    while (true) {
      for (final descriptor in scope._registry.values) {
        if (identical(descriptor.cachedInstance, instance)) return descriptor;
      }
      final parent = scope._parent;
      if (parent == null) {
        return bridge.findDescriptorByInstanceFromRoot(instance);
      }
      scope = parent;
    }
  }

  /// Unregisters and disposes the scope-local dependency of type [T].
  ///
  /// Only affects registrations made directly on this scope; parent scope
  /// and bridge registrations are untouched. Completes with `true` when a
  /// registration was removed, `false` when the scope had no such
  /// registration.
  Future<bool> unregister<T extends Object>({String? instanceName}) async {
    _ensureNotDisposed();
    final key = DependencyKey(T, instanceName);
    final descriptor = _registry.remove(key);
    if (descriptor == null) return false;
    bridge.notifyDependencyEvent(DependencyChangeKind.unregistered, descriptor);
    await descriptor.dispose();
    return true;
  }

  /// An unmodifiable snapshot of registration metadata for dependencies
  /// registered directly on this scope.
  List<DependencyInfo> get dependencyInfo => _registry.values
      .map((d) => DependencyInfo.fromDescriptor(d))
      .toList(growable: false);

  // ---------------------------------------------------------------------------
  // DISPOSAL
  // ---------------------------------------------------------------------------

  /// Disposes every dependency owned by this scope — including all child
  /// scopes — and marks it inactive.
  ///
  /// Dependencies are disposed in reverse registration order. Idempotent:
  /// calling [dispose] more than once is a no-op.
  ///
  /// When [disposeInstances] is false the registrations are dropped without
  /// running cached instances or `onDispose` hooks.
  Future<void> dispose({bool disposeInstances = true}) async {
    if (_isDisposed) return;
    _isDisposed = true;
    bridge.untrackScope(this);
    // A stacked scope disposed directly must leave the scope stack, otherwise
    // currentScope would keep returning this disposed scope and every
    // resolution through the bridge would throw.
    bridge.unstackScope(this);

    try {
      await onDisposeCallback?.call();
    } catch (error, stackTrace) {
      reportBridgeError(
        error,
        stackTrace,
        context: 'While running BridgeScope.dispose callback for $scopeName',
      );
    }

    for (final child in _children.toList().reversed) {
      await child.dispose(disposeInstances: disposeInstances);
    }
    _children.clear();
    _parent?._children.remove(this);

    _releaseShadowNotifications();
    final descriptors = _registry.values.toList()
      ..sort((a, b) => b.registrationIndex.compareTo(a.registrationIndex));
    for (final descriptor in descriptors) {
      bridge.notifyDependencyEvent(
          DependencyChangeKind.unregistered, descriptor);
      if (disposeInstances) {
        await descriptor.dispose();
      }
    }
    _registry.clear();
  }
}

/// Marker interface for instances that must signal their own readiness.
///
/// Implementing this is equivalent to passing `signalsReady: true` when
/// registering an eager singleton instance.
abstract class WillSignalReady {}

/// Immutable snapshot of a registered dependency's metadata.
@immutable()
final class DependencyInfo {
  /// Creates a [DependencyInfo] snapshot.
  const DependencyInfo({
    required this.key,
    required this.lifecycle,
    required this.registrationIndex,
    required this.isReady,
    required this.hasInstance,
    required this.hasAsyncResolution,
    required this.signalsReady,
    required this.dependsOn,
    this.ownerModuleName,
    this.scopeName,
    this.isDisposed = false,
  });

  /// Creates a snapshot from a live [DependencyDescriptor].
  factory DependencyInfo.fromDescriptor(DependencyDescriptor<dynamic> d) {
    return DependencyInfo(
      key: d.key,
      lifecycle: d.lifecycle,
      registrationIndex: d.registrationIndex,
      isReady: d.isReady,
      hasInstance: d.hasInstance,
      hasAsyncResolution: d.hasAsyncResolution,
      signalsReady: d.signalsReady,
      dependsOn: List.unmodifiable(d.dependsOn),
      ownerModuleName: d.ownerModuleName,
      scopeName: d.scopeName,
      isDisposed: d.isDisposed,
    );
  }

  /// Lookup key (type + optional name).
  final DependencyKey key;

  /// Lifetime strategy.
  final DependencyLifecycle lifecycle;

  /// Monotonic registration order.
  final int registrationIndex;

  /// Whether the dependency is currently ready.
  final bool isReady;

  /// Whether an instance has been created and cached.
  final bool hasInstance;

  /// Whether an async resolution is in-flight or completed.
  final bool hasAsyncResolution;

  /// Whether readiness requires a manual `signalReady` call.
  final bool signalsReady;

  /// Dependencies that must resolve before this registration's factory runs.
  final List<DependencyKey> dependsOn;

  /// Owning [FeatureModule] name, when registered by a module.
  final String? ownerModuleName;

  /// Owning [BridgeScope] name, when registered inside a scope.
  final String? scopeName;

  /// Whether the descriptor has been disposed.
  final bool isDisposed;

  @override
  String toString() => 'DependencyInfo(${key.toString()}, $lifecycle)';
}
